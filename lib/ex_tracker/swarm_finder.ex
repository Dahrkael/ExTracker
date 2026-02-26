# ExTracker.SwarmFinder is the process responsible for keeping track of all the swarms (torrents) using ETS
# tables are created and looked up here but the actual updates happen in ExTracker.Swarm
defmodule ExTracker.SwarmFinder do

  # ETS table to store the index for every swarm table containing the actual data
  @swarms_table_name :swarms
  def swarms_table_name, do: @swarms_table_name

  use GenServer
  require Logger

  alias ExTracker.Swarm
  alias ExTracker.Types.SwarmID
  alias ExTracker.Utils

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  #==========================================================================
  # Client
  #==========================================================================

  @spec find_or_create(hash :: binary()) :: {atom(), SwarmID.t()}
  def find_or_create(hash) do
    case :ets.lookup(@swarms_table_name, hash) do
      [{^hash, table, type, _created_at, _last_cleaned}] ->
        {:ok, SwarmID.new(hash, table, type)}
      _ ->
        create(hash)
    end
  end

  @spec find(hash :: binary()) :: {atom(), SwarmID.t()} | :error
  def find(hash) do
    case :ets.lookup(@swarms_table_name, hash) do
      [{^hash, table, type, _created_at, _last_cleaned}] ->
        {:ok, SwarmID.new(hash, table, type)}
      _ ->
        :error
    end
  end

  @spec remove(hash :: binary()) :: :ok | :error
  def remove(hash) do
    case :ets.lookup(@swarms_table_name, hash) do
      [{^hash, _table, _type, _created_at, _last_cleaned}] -> destroy(hash)
      _ -> :error
    end
  end

  def upgrade(hash) do
    GenServer.call(__MODULE__, {:upgrade, hash})
  end

  def downgrade(hash) do
    GenServer.call(__MODULE__, {:downgrade, hash})
  end

  @spec mark_as_clean(hash :: binary()) :: :ok | :error
  def mark_as_clean(hash) do
    case :ets.lookup(@swarms_table_name, hash) do
      [{^hash, _table, _type, _created_at, _last_cleaned}] -> clean(hash)
      _ -> :error
    end
  end

  @spec restore_creation_timestamp(hash :: binary(), timestamp :: any()) :: :ok | :error
  def restore_creation_timestamp(hash, timestamp) do
    case :ets.lookup(@swarms_table_name, hash) do
      [{^hash, _table, _type, _created_at, _last_cleaned}] -> restore(hash, timestamp)
      _ -> :error
    end
  end

  @spec get_swarm_creation_date(hash :: binary()) :: any()
  def get_swarm_creation_date(hash) do
    case :ets.lookup(@swarms_table_name, hash) do
      [{^hash, _, _, created_at, _}] -> created_at
      _ -> :error
    end
  end

  def get_swarm_list() do
    :ets.tab2list(@swarms_table_name)
    |> Enum.map(fn {hash, table, type, _created_at, _last_cleaned} ->
      SwarmID.new(hash, table, type)
    end)
  end

  def get_swarm_list_stream() do
    Stream.resource(
      fn -> # start
        #:ets.safe_fixtable(@swarms_table_name, true)
        :ets.first(@swarms_table_name)
      end,
      fn key -> # next
        case key do
          :"$end_of_table" ->
            {:halt, nil}
          _ ->
            result = case :ets.lookup(@swarms_table_name, key) do
              [{hash, table, type, _created_at, _last_cleaned}] ->
                SwarmID.new(hash, table, type)
              [] ->
                nil
            end
            next_key = :ets.next(@swarms_table_name, key)
            {[result], next_key}
        end
      end,
      fn _ -> # end
        #:ets.safe_fixtable(@swarms_table_name, false)
        :ok
      end
    )
  end

  def get_swarm_count() do
    :ets.info(@swarms_table_name, :size)
  end

  # optimization for SwarmCleaner
  def get_swarm_buckets() do
    GenServer.call(__MODULE__, {:get_buckets})
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

  defp create_buckets(count) when count < 1, do: {}
  defp create_buckets(count) do
      0..count - 1
      |> Enum.to_list()
      |> Enum.map(fn i ->
        # atom count has an upper limit so better make it optional for debug mostly
        table_name = case Application.get_env(:extracker, :named_lookups, ExTracker.debug_enabled()) do
          true -> :"swarm_bucket_#{i}}"
          false -> :swarm_small
        end

        ets_args = [:set, :public] ++ get_ets_compression_arg() ++ [write_concurrency: :auto]
        :ets.new(table_name, ets_args)
      end)
      |> List.to_tuple()
  end

  @impl true
  def init(_args) do
    # create the index table
    ets_args = [:set, :named_table, :protected] ++ get_ets_compression_arg()
    :ets.new(@swarms_table_name, ets_args)

    # create all the tables used to pool small swarms
    bucket_count = Application.get_env(:extracker, :small_swarm_buckets, 1000)
    buckets = create_buckets(bucket_count)

    state = %{buckets: buckets}
    Logger.notice("Using #{tuple_size(state.buckets)} buckets for small swarms optimization")
    {:ok, state}
  end

  @impl true
  def terminate(_reason, _state) do
  end

  @impl true
  def handle_call({:create, hash}, _from, state) do
    result = case check_allowed_hash(hash) do
      true ->
        table = create_swarm_checked(hash, state)
        {:ok, table}
      false ->
        {:error, :hash_not_allowed}
    end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:upgrade, hash}, _from, state) do
    result = case :ets.lookup(@swarms_table_name, hash) do
      [{^hash, table, :big, _created_at, _last_cleaned}] -> # swarm is already big
        SwarmID.new(hash, table, :big)
      [{^hash, table, :small, created_at, _last_cleaned}] ->
        upgrade_swarm(hash, table, created_at, state)
      _ -> # swarm doesnt exist
        :error
    end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:downgrade, hash}, _from, state) do
    result = case :ets.lookup(@swarms_table_name, hash) do
      [{^hash, table, :small, _created_at, _last_cleaned}] -> # swarm is already small
        SwarmID.new(hash, table, :small)
      [{^hash, table, :big, created_at, _last_cleaned}] ->
        downgrade_swarm(hash, table, created_at, state)
      _ -> # swarm doesnt exist
        :error
    end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:get_buckets}, _from, state) do
    {:reply, state.buckets, state}
  end

  @impl true
  def handle_cast({:destroy, hash}, state) do
    destroy_swarm(hash)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:clean, hash}, state) do
    timestamp = System.system_time(:millisecond)
    case :ets.update_element(@swarms_table_name, hash, [{5, timestamp}]) do
      true -> :ok
      false -> Logger.warning("failed to mark entry #{Utils.hash_to_string(hash)} as clean")
    end
    {:noreply, state}
  end

  @impl true
  def handle_cast({:restore, hash, created_at}, state) do
    case :ets.update_element(@swarms_table_name, hash, [{4, created_at}]) do
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
    case Application.get_env(:extracker, :restrict_hashes, "disabled") do
      "whitelist" -> ExTracker.Accesslist.contains(:whitelist_hashes, hash)
      "blacklist" -> !ExTracker.Accesslist.contains(:blacklist_hashes, hash)
      _ -> true
    end
  end

  # create the new swarm if it doesnt already exist
  # by default start as a small swarm except if there are no buckets
  defp create_swarm_checked(hash, state) do
    case :ets.lookup(@swarms_table_name, hash) do
      [{^hash, table, type, _created_at, _last_cleaned}] ->
        SwarmID.new(hash, table, type)
      _ ->
        case tuple_size(state.buckets) do
          0 -> create_swarm(hash, :big, state)
          _ -> create_swarm(hash, :small, state)
        end
    end
  end

  # get a bucket table for the new swarm and index it
  defp create_swarm(hash, :small, state) do
    # table HAS to exist at this point
    # TODO to get an even better distribution i can just do a round-robin index
    index = :erlang.phash2(hash) |> rem(tuple_size(state.buckets))
    table = elem(state.buckets, index)

    timestamp = System.system_time(:millisecond)
    :ets.insert(@swarms_table_name, {hash, table, :small, timestamp, timestamp})
    ExTracker.SwarmSnatches.init(hash)

    # TODO add new telemetry for big vs small swarms
    :telemetry.execute([:extracker, :swarm, :created], %{})
    Logger.debug("using bucket table #{index} for hash #{Utils.hash_to_string(hash)}")

    SwarmID.new(hash, table, :small)
  end

  # create a table for the new swarm and index it
  defp create_swarm(hash, :big, _state) do
    # atom count has an upper limit so better make it optional for debug mostly
    table_name = case Application.get_env(:extracker, :named_lookups, ExTracker.debug_enabled()) do
      true -> :"swarm_#{Utils.hash_to_string(hash)}"
      false -> :swarm_big
    end

    ets_args = [:set, :public] ++ get_ets_compression_arg() ++ [write_concurrency: :auto]
    table = :ets.new(table_name, ets_args)

    timestamp = System.system_time(:millisecond)
    :ets.insert(@swarms_table_name, {hash, table, :big, timestamp, timestamp})
    ExTracker.SwarmSnatches.init(hash)

    :telemetry.execute([:extracker, :swarm, :created], %{})
    Logger.debug("created table #{inspect(table_name)} for hash #{Utils.hash_to_string(hash)}")

    SwarmID.new(hash, table, :big)
  end

  # move the swarm from a bucket to its own table
  def upgrade_swarm(hash, table, created_at, state) do
    # retrieve all the peers from the current small swarm
    old_swarm = SwarmID.new(hash, table, :small)
    peers = Swarm.get_all_peers(old_swarm, true)

    # create the new big swarm (overrides the index)
    new_swarm = create_swarm(hash, :big, state)
    # restore the old creation date
    :ets.update_element(@swarms_table_name, hash, [{4, created_at}])

    # move the peers to the new swarm
    Enum.each(peers, fn {id, data} ->
      Swarm.insert_peer(new_swarm, {id, data}, false)
      Swarm.delete_peer(old_swarm, id)
    end)

    new_swarm
  end

  def downgrade_swarm(hash, table, created_at, state) do
    # retrieve all the peers from the current big swarm
    old_swarm = SwarmID.new(hash, table, :big)
    peers = Swarm.get_all_peers(old_swarm, true)

    # 'create' the new small swarm (overrides the index)
    new_swarm = create_swarm(hash, :small, state)
    # restore the old creation date
    :ets.update_element(@swarms_table_name, hash, [{4, created_at}])

    # move the peers to the new swarm
    Enum.each(peers, fn {id, data} ->
      Swarm.insert_peer(new_swarm, {id, data}, false)
      Swarm.delete_peer(old_swarm, id)
    end)

    # delete the old big swarm table
    :ets.delete(old_swarm.table)

    new_swarm
  end

  defp destroy_swarm(hash) do
    case :ets.lookup(@swarms_table_name, hash) do
      [{^hash, table, type, _created_at, _last_cleaned}] ->
        # delete the index entry
        :ets.delete(@swarms_table_name, hash)
        # delete the swarm table if it's not a shared one
        if type == :big do
          :ets.delete(table)
        end

        ExTracker.SwarmSnatches.delete(hash)

        :telemetry.execute([:extracker, :swarm, :destroyed], %{})
        Logger.debug("destroyed swarm for hash #{Utils.hash_to_string(hash)}")
      _ -> :notfound
    end
  end
end
