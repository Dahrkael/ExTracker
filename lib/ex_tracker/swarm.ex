defmodule ExTracker.Swarm do
  require Logger

  alias ExTracker.Types.PeerID
  alias ExTracker.Types.PeerData
  alias ExTracker.Types.SwarmID

  # try to find and retrieve a peer registered in the specified swarm
  @spec find_peer(swarm :: SwarmID.t(), id :: PeerID.t()) :: {:ok, PeerData} | :notfound
  def find_peer(swarm, id) do
    case lookup_peer(swarm, id) do
      [{_, data}] -> {:ok, data}
      _ -> :notfound
    end
  end

  # add a new peer to the specified swarm
  @spec add_peer(swarm :: SwarmID.t(), id :: PeerID.t()) :: {:ok, PeerData} | {:error, any()}
  def add_peer(swarm, id) do
    data = %PeerData{
      country: geoip_lookup_country(id.ip),
      last_updated: System.system_time(:millisecond)
    }

    peer = {id, data}
    case insert_peer(swarm, peer) do
      true ->
        :telemetry.execute([:extracker, :peer, :added], %{}, %{ family: id.family})
        {:ok, data}
      false -> {:error, "peer already exists"}
    end
  end

  defp geoip_lookup_country(ip) do
    case Application.get_env(:extracker, :geoip_enabled, false) do
      true ->
        case :locus.lookup(:country, ip) do
          {:ok, data} -> data["country"]["iso_code"]
          _ -> ""
        end
      false -> ""
    end
  end

  # remove an existing peer from the specified swarm
  @spec remove_peer(swarm :: SwarmID.t(), id :: PeerID.t()) :: :ok | :notfound
  def remove_peer(swarm, id) do
    with [{_, _data}] <- lookup_peer(swarm, id), true <- delete_peer(swarm, id) do
      :telemetry.execute([:extracker, :peer, :removed], %{}, %{ family: id.family})
      :ok
    else
      _ -> :notfound
    end
  end

  @spec update_peer(swarm :: SwarmID.t(), id :: PeerID.t(), data :: PeerData) :: {:ok, PeerData} | {:error, any()}
  def update_peer(swarm, id, data)  do
    # reflect when was the last update
    timestamp = System.system_time(:millisecond)
    data = PeerData.update_last_updated(data, timestamp)

    if(find_peer(swarm, id)) do
      case insert_peer(swarm, {id, data}) do
        true -> {:ok, data}
        false -> {:error, "peer insertion failed"}
      end
    end
    {:error, "peer not found in swarm"}
  end

  # peers may be in a shared table if there are not enough to be on their own
  # so before calling the ETS functions we need to append the hash to the key
  @spec get_peer_table_key(swarm :: SwarmID.t(), id :: PeerID.t()) :: any()
  defp get_peer_table_key(swarm, id) do
    sid = PeerID.to_storage(id)
    case swarm.type do
      :big -> sid
      :small -> {swarm.hash, sid}
    end
  end

  @spec lookup_peer(swarm :: SwarmID.t(), id :: PeerID.t()) :: any()
  defp lookup_peer(swarm, id) do
    key = get_peer_table_key(swarm, id)
    :ets.lookup(swarm.table, key)
  end

  @spec insert_peer(swarm :: SwarmID.t(), {id :: PeerID.t(), data :: PeerData}) :: boolean()
  defp insert_peer(swarm, {id, data}) do
    key = get_peer_table_key(swarm, id)
    :ets.insert_new(swarm.table, {key, data})
  end

  @spec delete_peer(swarm :: SwarmID.t(), {id :: PeerID.t()}) :: boolean()
  defp delete_peer(swarm, id) do
    key = get_peer_table_key(swarm, id)
    :ets.delete(swarm.table, key)
  end

  # get the total number of peers registered in the specified swarm filtered by ipv4 or ipv6
  def get_peer_count(swarm, family) do
    get_peers(swarm, :all, :all, family, false) |> length()
  end

  # get the total number of leechers registered in the specified swarm
  def get_leecher_count(swarm, family) do
    get_leechers(swarm, :all, family, false) |> length()
  end

  # get the total number of seeders registered in the specified swarm
  def get_seeder_count(swarm, family) do
    get_seeders(swarm, :all, family, false) |> length()
  end

  # get the total number of partial seeders registered in the specified swarm
  def get_partial_seeder_count(swarm, family) do
    get_partial_seeders(swarm, :all, family, false) |> length()
  end

  # return a list of all the peers registered in the swarm  up to 'count', optionally includes their associated data
  def get_peers(swarm, count, type, family, include_data) do
    spec_condition_type = case type do
      :leechers -> {:>, {:map_get, :left, :"$2"}, 0} # data.left > 0
      :seeders -> {:==, {:map_get, :left, :"$2"}, 0} # data.left == 0
      :partial_seeders -> {:==, {:map_get, :last_event, :"$2"}, :paused} # data.last_event == :paused
      :all -> nil # no condition
    end

    spec_condition_family = case family do
      :inet  -> {:==, {:binary_part, :"$1", 0, 1}, <<0x04>>} # id.family == :inet
      :inet6 -> {:==, {:binary_part, :"$1", 0, 1}, <<0x06>>} # id.family == :inet6
      :all -> nil # no condition
    end

    #spec_condition_family = case family do
    #  :inet -> {:==, {:map_get, :family, :"$1"}, :inet} # id.family == :inet
    #  :inet6 -> {:==, {:map_get, :family, :"$1"}, :inet6} # id.family == :inet6
    #  :all -> nil # no condition
    #end

    # [{:andalso,{:>, {:map_get, :left, :"$2"}, 0},{:==, {:map_get, :family, :"$1"}, :inet}}]
    spec_condition = case {spec_condition_type, spec_condition_family} do
      {nil, nil} -> []
      {cond1, nil} -> [cond1]
      {nil, cond2} -> [cond2]
      {cond1, cond2} -> [{:andalso, cond1, cond2}]
    end

    spec_match = case include_data do
      false -> [:"$1"] # peer.id
      true -> [:"$_"] # peer
    end

    # make the whole spec with the pieces
    spec = [{{:"$1", :"$2"}, spec_condition, spec_match}]

    # execute the specified request
    try do
      result = case count do
        :all -> :ets.select(swarm, spec)
        integer -> :ets.select(swarm, spec, integer)
      end

      # convert the IDs back to the normal type
      case include_data do
        false ->
          Enum.map(result, fn sid -> PeerID.from_storage(sid) end)
        true ->
          Enum.map(result, fn {sid, data} -> {PeerID.from_storage(sid), data} end)
      end

    rescue
      # the swarm table may be gone while the query reaches this point
      e in ArgumentError ->
        Logger.debug("get_peers/5: #{Exception.message(e)}")
        []
    end
  end

  def get_all_peers(swarm, include_data) do
    get_peers(swarm, :all, :all, :all, include_data)
  end

  def get_leechers(swarm, count, family, include_data) do
    get_peers(swarm, count, :leechers, family, include_data)
  end

  def get_seeders(swarm, count, family, include_data) do
    get_peers(swarm, count, :seeders, family, include_data)
  end

  def get_partial_seeders(swarm, count, family, include_data) do
    get_peers(swarm, count, :partial_seeders, family, include_data)
  end

  def get_stale_peers(swarm, timestamp) do
    #spec = :ets.fun2ms(fn {id, data} = peer when data.last_updated < timestamp -> peer end)
    spec = [{{:"$1", :"$2"}, [{:<, {:map_get, :last_updated, :"$2"}, timestamp}], [:"$_"]}]
    :ets.select(swarm, spec)
    # convert the IDs back to the normal type
    |> Enum.map(fn {sid, data} ->
      {PeerID.from_storage(sid), data}
    end)
  end
end
