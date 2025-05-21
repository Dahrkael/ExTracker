defmodule ExTracker.Swarm do
  alias ExTracker.Types.PeerData

  # try to find and retrieve a peer registered in the specified swarm
  @spec find_peer(swarm :: any(), id :: PeerID) :: {:ok, PeerData} | :notfound
  def find_peer(swarm, id) do
    case :ets.lookup(swarm, id) do
      [{_, data}] -> {:ok, data}
      _ -> :notfound
    end
  end

  # add a new peer to the specified swarm
  @spec add_peer(swarm :: any(), id :: PeerID) :: {:ok, PeerData} | {:error, any()}
  def add_peer(swarm, id) do
    data = %PeerData{
      country: geoip_lookup_country(id.ip),
      last_updated: System.system_time(:millisecond)
    }

    peer = {id, data}
    case :ets.insert_new(swarm, peer) do
      true -> {:ok, data}
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
  @spec remove_peer(swarm :: any(), id :: PeerID) :: :ok | :notfound
  def remove_peer(swarm, id) do
    with [{_, _data}] <- :ets.lookup(swarm, id),
         true <- :ets.delete(swarm, id) do
      :ok
    else
      _ -> :notfound
    end
  end

  @spec update_peer(swarm :: any(), id :: PeerID, data :: PeerData) :: {:ok, PeerData} | {:error, any()}
  def update_peer(swarm, id, data)  do
    # reflect when was the last update
    timestamp = System.system_time(:millisecond)
    data = PeerData.update_last_updated(data, timestamp)

    if(find_peer(swarm, id)) do
      case :ets.insert(swarm, {id, data}) do
        true -> {:ok, data}
        false -> {:error, "peer insertion failed"}
      end
    end
    {:error, "peer not found in swarm"}
  end

  # get the total number of peers registered in the specified swarm
  def get_peer_count(swarm) do
    :ets.info(swarm, :size)
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

  # return a list of all the peers registered in the swarm  up to 'count', optionally includes their associated data
  def get_peers(swarm, count, type, family, include_data) do
    spec_condition_type = case type do
      :leechers -> {:>, {:map_get, :left, :"$2"}, 0} # data.left > 0
      :seeders -> {:==, {:map_get, :left, :"$2"}, 0} # data.left == 0
      :all -> nil # no condition
    end

    spec_condition_family = case family do
      :inet -> {:==, {:map_get, :family, :"$1"}, :inet} # id.family == :inet
      :inet6 -> {:==, {:map_get, :family, :"$1"}, :inet6} # id.family == :inet6
      :all -> nil # no condition
    end

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
    case count do
      :all -> :ets.select(swarm, spec)
      integer -> :ets.select(swarm, spec, integer)
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

  def get_stale_peers(swarm, timestamp) do
    #spec = :ets.fun2ms(fn {id, data} = peer when data.last_updated < timestamp -> peer end)
    spec = [{{:"$1", :"$2"}, [{:<, {:map_get, :last_updated, :"$2"}, timestamp}], [:"$_"]}]
    :ets.select(swarm, spec)
  end
end
