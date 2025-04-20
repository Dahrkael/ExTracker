defmodule ExTracker.SwarmFinder do

  # ETS table to store the index for every swarm table containing the actual data
  @swarms_table_name :swarms

  use GenServer
  require Logger

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  #==========================================================================
  # Client
  #==========================================================================

  def find_or_create(hash) do
    case :ets.lookup(@swarms_table_name, hash) do
      [{^hash, table, _timestamp}] -> table
      _ -> create(hash)
    end
  end

  def find(hash) do
    case :ets.lookup(@swarms_table_name, hash) do
      [{^hash, table, _timestamp}] -> table
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

  #==========================================================================
  # Server (callbacks)
  #==========================================================================

  @impl true
  def init(_args) do
    :ets.new(@swarms_table_name, [:set, :named_table, :protected])
    {:ok, {}}
  end

  @impl true
  def terminate(_reason, _state) do
  end

  @impl true
  def handle_call({:create, hash}, _from, state) do
    table = create_swarm_checked(hash)
    {:reply, table, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # create a table for the new swarm if it doesnt already exist
  defp create_swarm_checked(hash) do
    case :ets.lookup(@swarms_table_name, hash) do
      [{^hash, table}] -> table
      _ -> create_swarm(hash)
    end
  end

  # create a table for the new swarm and index it
  defp create_swarm(hash) do
    table = :ets.new(:swarm, [:set, :public])
    timestamp = System.system_time(:millisecond)
    :ets.insert(@swarms_table_name, {hash, table, timestamp})
    table
  end
end
