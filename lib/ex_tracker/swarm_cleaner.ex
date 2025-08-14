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
      GenServer.cast(__MODULE__, {:clean_all})
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
      # select all the tables that are due for a clean up
      now = System.system_time(:millisecond)
      swarm_timeout = now - Application.get_env(:extracker, :swarm_clean_delay)
      peer_timeout = now - Application.get_env(:extracker, :peer_cleanup_delay)

      start = System.monotonic_time(:millisecond)
      #spec = :ets.fun2ms(fn {hash, table, type, created_at, last_cleaned} = swarm when last_cleaned < swarm_timeout  -> swarm end)
      spec = [{{:"$1", :"$2", :"$3", :"$4", :"$5"}, [{:<, :"$4", swarm_timeout}], [:"$_"]}]
      entries = :ets.select(SwarmFinder.swarms_table_name(), spec)

      entry_count = length(entries)
      if (entry_count > 0) do
        elapsed = System.monotonic_time(:millisecond) - start
        Logger.debug("swarm cleaner found #{entry_count} swarms pending cleaning in #{elapsed}ms")
      end

      # retrieve the peers inside every matching swarm in parallel
      entries
      |> Task.async_stream(fn {hash, table, type, _created_at, _last_cleaned} ->
        swarm = SwarmID.new(hash, table, type)
        Swarm.get_stale_peers(swarm,  peer_timeout)
        |> (fn stale_peers ->
          peer_count = length(stale_peers)
          if peer_count > 0 do
            Logger.debug("removing #{length(stale_peers)} stale peers from swarm #{Utils.hash_to_string(hash)}")
          end
          stale_peers
        end).()
        # remove the stale ones
        |> Enum.each(fn peer ->
          {id, _data} = peer
          Swarm.remove_peer(swarm, id)
        end)

        # flag the swarm as clean
          SwarmFinder.mark_as_clean(swarm.hash)
        # trigger different logic based on the swarm type after cleaning
        swarm_cleaned(swarm)
      end, max_concurrency: System.schedulers_online())
      |> Stream.run()

      if (entry_count > 0) do
        elapsed = System.monotonic_time(:millisecond) - start
        Logger.info("swarm cleaner processed #{entry_count} swarms in #{elapsed}ms")
      end

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
    def handle_cast(:clean_all, state) do
      # TODO
      {:noreply, state}
    end

    defp swarm_cleaned(%{type: type} = swarm) when type == :big do
      peer_limit = get_downgrade_threshold()
      peer_count = Swarm.get_peer_count(swarm, :all)
      cond do
        peer_count == 0 ->
          # empty swarms are deleted right away
          SwarmFinder.remove(swarm.hash)
        peer_count < peer_limit ->
          case SwarmFinder.downgrade(swarm.hash) do
            :error ->
              Logger.error("failed to downgrade swarm #{Utils.hash_to_string(swarm.hash)} containing #{peer_count} peers")
            _new_swarm ->
              Logger.info("downgraded swarm #{Utils.hash_to_string(swarm.hash)} containing #{peer_count} peers")
          end
        true ->
          :ok # nothing to do
      end
    end

    defp swarm_cleaned(%{type: type} = swarm) when type == :small do
      peer_limit = get_upgrade_threshold()
      peer_count = Swarm.get_peer_count(swarm, :all)
      cond do
        peer_count == 0 ->
          # empty swarms are deleted right away
          SwarmFinder.remove(swarm.hash)
        peer_count >= peer_limit ->
          case SwarmFinder.upgrade(swarm.hash) do
            :error ->
              Logger.error("failed to upgrade swarm #{Utils.hash_to_string(swarm.hash)} containing #{peer_count} peers")
            _new_swarm ->
              Logger.info("upgraded swarm #{Utils.hash_to_string(swarm.hash)} containing #{peer_count} peers")
          end
        true ->
          :ok # nothing to do
      end
    end
  end
