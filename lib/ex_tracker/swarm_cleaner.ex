# ExTracker.SwarmCleaner is the process responsible for periodically removing old peers and swarms
# it is also in charge of upgrading and downgrading swarms based on how many peers they have left
defmodule ExTracker.SwarmCleaner do

    use GenServer
    require Logger

    alias ExTracker.Swarm
    alias ExTracker.SwarmFinder
    alias ExTracker.Utils
    alias ExTracker.Types.SwarmID

    def start_link(args) do
      GenServer.start_link(__MODULE__, args, name: __MODULE__)
    end

    #==========================================================================
    # Client
    #==========================================================================

    def clean(hash) do
      GenServer.cast(__MODULE__, {:clean, hash})
    end

    def clean_all() do
      GenServer.call(__MODULE__, :clean_all, 300_000)
    end

    #==========================================================================
    # Server (callbacks)
    #==========================================================================

    @impl true
    def init(_args) do
      if(get_downgrade_threshold() >= get_upgrade_threshold()) do
        reason = "required peer count to downgrade swarms is higher than the count to upgrade them. that makes no sense"
        Logger.error(reason)
        {:error, reason}
      else
        schedule_clean()
        {:ok, {}}
      end
    end

    defp get_upgrade_threshold() do
      Application.get_env(:extracker, :swarm_upgrade_peer_threshold, 100)
    end

    defp get_downgrade_threshold() do
      down_threshold = Application.get_env(:extracker, :swarm_downgrade_percentage_threshold, 0.75)
      get_upgrade_threshold() * down_threshold
    end

    @impl true
    def terminate(_reason, _state) do
    end

    defp schedule_clean() do
      Process.send_after(self(), :clean, Application.get_env(:extracker, :cleaning_interval))
    end

    @impl true
    def handle_info(:clean, state) do
      #:eprof.start_profiling([self()])

      [&clean_swarms_big/0, &clean_swarms_small/0]
      |> Task.async_stream(& &1.(), ordered: false, timeout: :infinity)
      |> Stream.run()

      #:eprof.stop_profiling()
      #:eprof.analyze(:total)

      schedule_clean()
      {:noreply, state}
    end

    @impl true
    def handle_info(_msg, state) do
      {:noreply, state}
    end

    @impl true
    def handle_cast({:clean, _hash}, state) do
      # TODO
      {:noreply, state}
    end

    @impl true
    def handle_call(:clean_all, _from, state) do
      handle_info(:clean, state)
      {:reply, :ok, state}
    end

    def clean_swarms_small() do
      now = System.system_time(:millisecond)
      swarm_timeout = now - Application.get_env(:extracker, :swarm_clean_delay)
      peer_timeout = now - Application.get_env(:extracker, :peer_cleanup_delay)

      start = System.monotonic_time(:millisecond)
      # sweep small swarm tables as a whole instead of per-swarm
      total_removed =
        SwarmFinder.get_swarm_buckets()
        |> Tuple.to_list()
        |> Task.async_stream(fn bucket ->
          remove_stale_peers(bucket, peer_timeout)
        end,
          max_concurrency: System.schedulers_online() * 2,
          ordered: false,
          timeout: :infinity)
        |> Enum.map(&elem(&1, 1))
        |> Enum.reduce(fn removed, total ->
          total + removed
        end)

      if (total_removed > 0) do
        elapsed = System.monotonic_time(:millisecond) - start
        Logger.debug("swarm cleaner removed #{total_removed} stale peers from small swarms in #{elapsed}ms")
      end

      # select all the swarms that are due for a clean up
      #spec = :ets.fun2ms(fn {hash, table, type, created_at, last_cleaned} = swarm when type == :small and last_cleaned < swarm_timeout -> swarm end)
      spec = [{{:"$1", :"$2", :"$3", :"$4", :"$5"}, [{:andalso, {:==, :"$3", :small}, {:<, :"$5", swarm_timeout}}], [:"$_"]}]
      entries = :ets.select(SwarmFinder.swarms_table_name(), spec)
      entry_count = length(entries)

      entries
      |> Task.async_stream(fn {hash, table, type, _created_at, _last_cleaned} ->
        swarm = SwarmID.new(hash, table, type)
        # flag the swarm as clean
        SwarmFinder.mark_as_clean(swarm.hash)
        # trigger post-clean logic
        swarm_cleaned(swarm)
      end,
        max_concurrency: System.schedulers_online() * 2,
        ordered: false)
      |> Stream.run()

      if (entry_count > 0) do
        elapsed = System.monotonic_time(:millisecond) - start
        Logger.debug("swarm cleaner processed #{entry_count} small swarms in #{elapsed}ms")
      end
    end

    def clean_swarms_big() do
      now = System.system_time(:millisecond)
      swarm_timeout = now - Application.get_env(:extracker, :swarm_clean_delay)
      peer_timeout = now - Application.get_env(:extracker, :peer_cleanup_delay)

      start = System.monotonic_time(:millisecond)
      # select all the swarms that are due for a clean up
      #spec = :ets.fun2ms(fn {hash, table, type, created_at, last_cleaned} = swarm when type == :big and last_cleaned < swarm_timeout -> swarm end)
      spec = [{{:"$1", :"$2", :"$3", :"$4", :"$5"}, [{:andalso, {:==, :"$3", :big}, {:<, :"$5", swarm_timeout}}], [:"$_"]}]
      entries = :ets.select(SwarmFinder.swarms_table_name(), spec)
      entry_count = length(entries)

      # remove the peers inside every matching swarm in parallel
      entries
      |> Task.async_stream(fn {hash, table, type, _created_at, _last_cleaned} ->
        swarm = SwarmID.new(hash, table, type)
        removed = remove_stale_peers(swarm.table, peer_timeout)
        #if removed > 0 do
          Logger.debug("swarm cleaner removed #{removed} stale peers from swarm #{Utils.hash_to_string(swarm.hash)}")
        #end

        # flag the swarm as clean
        SwarmFinder.mark_as_clean(swarm.hash)
        # trigger post-clean logic
        swarm_cleaned(swarm)
      end,
        max_concurrency: System.schedulers_online() * 2,
        ordered: false)
      |> Stream.run()

      if (entry_count > 0) do
        elapsed = System.monotonic_time(:millisecond) - start
        Logger.debug("swarm cleaner processed #{entry_count} big swarms in #{elapsed}ms")
      end
    end

    @spec remove_stale_peers(table :: :ets.tid(), timestamp :: any()) :: non_neg_integer()
    def remove_stale_peers(table, timestamp) do
      # we do not care about ids or hashes here, just the timestamp
      spec_head = {:"$1", :"$2"}
      spec_condition = [{:<, {:map_get, :last_updated, :"$2"}, timestamp}]
      spec_match = [true]
      # make the whole spec with the pieces
      spec = [{spec_head, spec_condition, spec_match}]

      # sweep the whole table in one single query to avoid wasting time
      #matches = :ets.select(table, spec)
      #IO.inspect(matches, label: "matches")
      :ets.select_delete(table, spec)
    end

    defp swarm_cleaned(%{type: type} = swarm) when type == :big do
      peer_limit = get_downgrade_threshold()
      peer_count = Swarm.get_all_peer_count(swarm, :all)
      cond do
        peer_count == 0 ->
          # empty swarms are deleted right away
          SwarmFinder.remove(swarm.hash)
        peer_count < peer_limit ->
          case SwarmFinder.downgrade(swarm.hash) do
            :error ->
              Logger.error("failed to downgrade swarm #{Utils.hash_to_string(swarm.hash)} containing #{peer_count} peers")
            _new_swarm ->
              Logger.debug("downgraded swarm #{Utils.hash_to_string(swarm.hash)} containing #{peer_count} peers")
          end
        true ->
          :ok # nothing to do
      end
    end

    defp swarm_cleaned(%{type: type} = swarm) when type == :small do
      peer_limit = get_upgrade_threshold()
      peer_count = Swarm.get_all_peer_count(swarm, :all)
      cond do
        peer_count == 0 ->
          # empty swarms are deleted right away
          SwarmFinder.remove(swarm.hash)
        peer_count >= peer_limit ->
          case SwarmFinder.upgrade(swarm.hash) do
            :error ->
              Logger.error("failed to upgrade swarm #{Utils.hash_to_string(swarm.hash)} containing #{peer_count} peers")
            _new_swarm ->
              Logger.debug("upgraded swarm #{Utils.hash_to_string(swarm.hash)} containing #{peer_count} peers")
          end
        true ->
          :ok # nothing to do
      end
    end
  end
