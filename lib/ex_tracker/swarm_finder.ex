# ExTracker.SwarmFinder is the process responsible for keeping track of all the swarms (torrents) using ETS
# tables are created and looked up here but the actual updates happen in ExTracker.Swarm<
defmodule ExTracker.SwarmFinder do

  # ETS table to store the index for every swarm table containing the actual data
  @swarms_table_name :swarms
  def swarms_table_name, do: @swarms_table_name

  use GenServer
  require Logger

  alias ExTracker.Utils

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  #==========================================================================
  # Client
  #==========================================================================

  def find_or_create(hash) do
    case :ets.lookup(@swarms_table_name, hash) do
      [{^hash, table, _created_at, _last_cleaned}] -> {:ok, table}
      _ -> create(hash)
    end
  end

  def find(hash) do
    case :ets.lookup(@swarms_table_name, hash) do
      [{^hash, table, _created_at, _last_cleaned}] -> table
      _ -> :error
    end
  end

  def remove(hash) do
    case :ets.lookup(@swarms_table_name, hash) do
      [{^hash, _table, _created_at, _last_cleaned}] -> destroy(hash)
      _ -> :error
    end
  end

  def mark_as_clean(hash) do
    case :ets.lookup(@swarms_table_name, hash) do
      [{^hash, _table, _created_at, _last_cleaned}] -> clean(hash)
      _ -> :error
    end
  end

  def restore_creation_timestamp(hash, timestamp) do
    case :ets.lookup(@swarms_table_name, hash) do
      [{^hash, _table, _created_at, _last_cleaned}] -> restore(hash, timestamp)
      _ -> :error
    end
  end

  def get_swarm_list() do
    :ets.tab2list(@swarms_table_name)
  end

  def get_swarm_count() do
    :ets.tab2list(@swarms_table_name) |> length()
  end

  defp create(hash) do
    GenServer.call(__MODULE__, {:create, hash})
  end

  defp destroy(hash) do
    GenServer.cast(__MODULE__, {:destroy, hash})
  end

  defp clean(hash) do
    GenServer.cast(__MODULE__, {:clean, hash})
  end

  defp restore(hash, created_at) do
    GenServer.cast(__MODULE__, {:restore, hash, created_at})
  end

  #==========================================================================
  # Server (callbacks)
  #==========================================================================

  defp get_ets_compression_arg() do
    if Application.get_env(:extracker, :compress_lookups, true) do
      [:compressed]
    else
      []
    end
  end

  @impl true
  def init(_args) do
    ets_args = [:set, :named_table, :protected] ++ get_ets_compression_arg()
    :ets.new(@swarms_table_name, ets_args)

    state = %{}
    {:ok, state}
  end

  @impl true
  def terminate(_reason, _state) do
  end

  @impl true
  def handle_call({:create, hash}, _from, state) do
    result = case check_allowed_hash(hash) do
      true ->
        table = create_swarm_checked(hash)
        {:ok, table}
      false ->
        {:error, :hash_not_allowed}
    end

    {:reply, result, state}
  end

  @impl true
  def handle_cast({:destroy, hash}, state) do
    destroy_swarm(hash)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:clean, hash}, state) do
    timestamp = System.system_time(:millisecond)
    case :ets.update_element(@swarms_table_name, hash, [{4, timestamp}]) do
      true -> :ok
      false -> Logger.warning("failed to mark entry #{Utils.hash_to_string(hash)} as clean")
    end
    {:noreply, state}
  end

  @impl true
  def handle_cast({:restore, hash, created_at}, state) do
    case :ets.update_element(@swarms_table_name, hash, [{3, created_at}]) do
      true -> :ok
      false -> Logger.warning("failed to update creation time for entry #{Utils.hash_to_string(hash)}")
    end
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp check_allowed_hash(hash) do
    case Application.get_env(:extracker, :restrict_hashes, false) do
      "whitelist" -> ExTracker.Accesslist.contains(:whitelist_hashes, hash)
      "blacklist" -> !ExTracker.Accesslist.contains(:blacklist_hashes, hash)
      _ -> true
    end
  end

  # create a table for the new swarm if it doesnt already exist
  defp create_swarm_checked(hash) do
    case :ets.lookup(@swarms_table_name, hash) do
      [{^hash, table, _created_at, _last_cleaned}] -> table
      _ -> create_swarm(hash)
    end
  end

  # create a table for the new swarm and index it
  defp create_swarm(hash) do
    # atom count has an upper limit so better make it optional for debug mostly
    table_name = case Application.get_env(:extracker, :named_lookups, ExTracker.debug_enabled()) do
      true -> :"swarm_#{hash |> Base.encode16() |> String.downcase()}"
      false -> :swarm
    end

    ets_args = [:set, :public] ++ get_ets_compression_arg()
    table = :ets.new(table_name, ets_args)

    timestamp = System.system_time(:millisecond)
    :ets.insert(@swarms_table_name, {hash, table, timestamp, timestamp})

    :telemetry.execute([:extracker, :swarm, :created], %{})
    Logger.debug("created table #{inspect(table_name)} for hash #{hash |> Base.encode16() |> String.downcase()}")

    table
  end

  defp destroy_swarm(hash) do
    case :ets.lookup(@swarms_table_name, hash) do
      [{^hash, table, _created_at, _last_cleaned}] ->
        # delete the index entry
        :ets.delete(@swarms_table_name, hash)
        # delete the swarm table
        :ets.delete(table)

        :telemetry.execute([:extracker, :swarm, :destroyed], %{})
        Logger.debug("destroyed swarm for hash #{hash |> Base.encode16() |> String.downcase()}")
      _ -> :notfound
    end
  end
end
