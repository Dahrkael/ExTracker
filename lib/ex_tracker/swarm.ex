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
    case insert_peer(swarm, peer, false) do # false because true is exponentially slower
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
      case insert_peer(swarm, {id, data}, false) do
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

  # internal
  @spec insert_peer(swarm :: SwarmID.t(), {id :: PeerID.t(), data :: PeerData}, new :: boolean()) :: boolean()
  def insert_peer(swarm, {id, data}, new) do
    key = get_peer_table_key(swarm, id)
    case new do
      true -> :ets.insert_new(swarm.table, {key, data})
      false -> :ets.insert(swarm.table, {key, data})
    end
  end

  # internal
  @spec delete_peer(swarm :: SwarmID.t(), {id :: PeerID.t()}) :: boolean()
  def delete_peer(swarm, id) do
    key = get_peer_table_key(swarm, id)
    :ets.delete(swarm.table, key)
  end

  def get_peer_count(%SwarmID{type: :big} = swarm, :all, :all) do
    :ets.info(swarm.table, :size)
  end
  # get the total number of peers registered in the specified swarm filtered by ipv4 or ipv6
  @spec get_peer_count(swarm :: SwarmID.t(), type :: atom(), family :: atom()) :: non_neg_integer()
  def get_peer_count(swarm, type, family) do
    # on small swarms the peer id is on the second position of the first (key) tuple
    peer_id_element = case swarm.type do
      :big -> :"$1"
      :small -> :"$3"
    end

    spec_head = case swarm.type do
      :big -> {:"$1", :"$2"}
      :small -> {{:"$1", :"$3"}, :"$2"}
    end

    # on small swarms the first position of the first tuple is their swarm hash
    spec_condition_hash = case swarm.type do
      :small -> {:==, :"$1", swarm.hash}
      :big -> nil # no need for a condition
    end

    spec_condition_type = case type do
      :leechers -> {:>, {:map_get, :left, :"$2"}, 0} # data.left > 0
      :seeders -> {:==, {:map_get, :left, :"$2"}, 0} # data.left == 0
      :partial_seeders -> {:==, {:map_get, :last_event, :"$2"}, :paused} # data.last_event == :paused
      :all -> nil # no condition
    end

    spec_condition_family = case family do
      :inet  -> {:==, {:binary_part, peer_id_element, 0, 1}, <<0x04>>} # id.family == :inet
      :inet6 -> {:==, {:binary_part, peer_id_element, 0, 1}, <<0x06>>} # id.family == :inet6
      :all -> nil # no condition
    end

    spec_condition =
      Enum.filter([spec_condition_type, spec_condition_family, spec_condition_hash], & &1)
      |> case do
        [] -> []
        [one] -> [one]
        [one, two] -> [{:andalso, one, two}]
        three -> [three |> Enum.reverse() |> Enum.reduce(fn other, previous -> {:andalso, previous, other} end)]
      end

    spec_match = [true]

    # make the whole spec with the pieces
    spec = [{spec_head, spec_condition, spec_match}]

    # execute the specified request
    try do
      :ets.select_count(swarm.table, spec)
    rescue
      # the swarm table may be gone while the query reaches this point
      e in ArgumentError ->
        Logger.debug("get_peer_count/5: #{Exception.message(e)}")
        0
    end
  end

  def get_all_peer_count(swarm, family) do
    get_peer_count(swarm, :all, family)
  end

  # get the total number of leechers registered in the specified swarm
  @spec get_leecher_count(swarm :: SwarmID.t(), family :: atom()) :: non_neg_integer()
  def get_leecher_count(swarm, family) do
    get_peer_count(swarm, :leechers, family)
  end

  # get the total number of seeders registered in the specified swarm
  @spec get_seeder_count(swarm :: SwarmID.t(), family :: atom()) :: non_neg_integer()
  def get_seeder_count(swarm, family) do
    get_peer_count(swarm, :seeders, family)
  end

  # get the total number of partial seeders registered in the specified swarm
  @spec get_partial_seeder_count(swarm :: SwarmID.t(), family :: atom()) :: non_neg_integer()
  def get_partial_seeder_count(swarm, family) do
    get_peer_count(swarm, :partial_seeders, family)
  end

  # return a list of all the peers registered in the swarm  up to 'count', optionally includes their associated data
  @spec get_peers(swarm :: SwarmID.t(), count :: :all | non_neg_integer(), type :: atom(), family :: atom(), include_data :: boolean()) :: list()
  def get_peers(swarm, count, type, family, include_data) do
    # on small swarms the peer id is on the second position of the first (key) tuple
    peer_id_element = case swarm.type do
      :big -> :"$1"
      :small -> :"$3"
    end

    spec_head = case swarm.type do
      :big -> {:"$1", :"$2"}
      :small -> {{:"$1", :"$3"}, :"$2"}
    end

    # on small swarms the first position of the first tuple is their swarm hash
    spec_condition_hash = case swarm.type do
      :small -> {:==, :"$1", swarm.hash}
      :big -> nil # no need for a condition
    end

    spec_condition_type = case type do
      :leechers -> {:>, {:map_get, :left, :"$2"}, 0} # data.left > 0
      :seeders -> {:==, {:map_get, :left, :"$2"}, 0} # data.left == 0
      :partial_seeders -> {:==, {:map_get, :last_event, :"$2"}, :paused} # data.last_event == :paused
      :all -> nil # no condition
    end

    spec_condition_family = case family do
      :inet  -> {:==, {:binary_part, peer_id_element, 0, 1}, <<0x04>>} # id.family == :inet
      :inet6 -> {:==, {:binary_part, peer_id_element, 0, 1}, <<0x06>>} # id.family == :inet6
      :all -> nil # no condition
    end

    spec_condition =
      Enum.filter([spec_condition_type, spec_condition_family, spec_condition_hash], & &1)
      |> case do
        [] -> []
        [one] -> [one]
        [one, two] -> [{:andalso, one, two}]
        three -> [three |> Enum.reverse() |> Enum.reduce(fn other, previous -> {:andalso, previous, other} end)]
      end

    spec_match = case include_data do
      false -> [peer_id_element] # peer.id
      true -> [{{peer_id_element, :"$2"}}] # peer
    end

    # make the whole spec with the pieces
    spec = [{spec_head, spec_condition, spec_match}]

    # execute the specified request
    try do
      result = case count do
        :all -> :ets.select(swarm.table, spec)
        integer -> :ets.select(swarm.table, spec, integer)
      end

      # convert the IDs back to the normal type
      case include_data do
        false ->
          Enum.map(result, &PeerID.from_storage/1)
        true ->
          Enum.map(result, fn {sid, data} -> {PeerID.from_storage(sid), data} end)
      end
      
      # inject fake peers according to the amount in the config
      |> case do
          list ->
            fake_peers_amount = Application.get_env(:extracker, :fake_peers_in_responses, 0)
            if fake_peers_amount > 0 do
              fake_peers = for _ <- 1..fake_peers_amount,
                              do: <<0x04, :rand.uniform(255), :rand.uniform(255), :rand.uniform(255), :rand.uniform(255)>>
              list ++ fake_peers
            else
              list
            end
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

  @spec get_stale_peers(swarm :: SwarmID.t(), timestamp :: any()) :: list()
  def get_stale_peers(swarm, timestamp) do
    # on small swarms the peer id is on the second position of the first (key) tuple
    peer_id_element = case swarm.type do
      :big -> :"$1"
      :small -> :"$3"
    end

    spec_head = case swarm.type do
      :big -> {:"$1", :"$2"}
      :small -> {{:"$1", :"$3"}, :"$2"}
    end

    # on small swarms the first position of the first tuple is their swarm hash
    spec_condition_hash = case swarm.type do
      :small -> {:==, :"$1", swarm.hash}
      :big -> nil # no need for a condition
    end

    spec_condition_timestamp = {:<, {:map_get, :last_updated, :"$2"}, timestamp}

    spec_condition = case spec_condition_hash do
      nil -> [spec_condition_timestamp]
      _cond -> [{:andalso, spec_condition_hash, spec_condition_timestamp}]
    end

    spec_match = [{{peer_id_element, :"$2"}}]
    # make the whole spec with the pieces
    spec = [{spec_head, spec_condition, spec_match}]

    :ets.select(swarm.table, spec)
    |> Enum.map(fn {sid, data} ->
      {PeerID.from_storage(sid), data}
    end)
  end
end
