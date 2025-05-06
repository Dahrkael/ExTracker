# ExTracker.SwarmCleaner is the process responsible for periodically removing old peers and swarms
# in the future swarms could be saved to disk instead of being wiped
defmodule ExTracker.SwarmCleaner do

    use GenServer
    require Logger

    alias ExTracker.Swarm
    alias ExTracker.SwarmFinder
    alias ExTracker.Utils

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
      schedule_clean()
      {:ok, {}}
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

      #spec = :ets.fun2ms(fn {hash, table, created_at, last_cleaned} = swarm when last_cleaned < tswarm_timeoutarget  -> swarm end)
      spec = [{{:"$1", :"$2", :"$3", :"$4"}, [{:<, :"$4", swarm_timeout}], [:"$_"]}]
      entries = :ets.select(SwarmFinder.swarms_table_name(), spec)

      entry_count = length(entries)
      if (entry_count > 0) do
        Logger.debug("swarm cleaner found #{entry_count} swarms pending cleaning")
      end

      # retrieve the peers inside every matching swarm in parallel
      entries
      |> Task.async_stream(fn entry ->
        {hash, table, _created_at, _last_cleaned} = entry
        Swarm.get_stale_peers(table,  peer_timeout)
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
          Swarm.remove_peer(table, id)
        end)

        # flag the swarm as clean
        SwarmFinder.mark_as_clean(hash)
      end)
      |> Stream.run()

      schedule_clean()
      {:noreply, state}
    end

    @impl true
    def handle_info(_msg, state) do
      {:noreply, state}
    end
  end
