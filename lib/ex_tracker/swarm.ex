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
    data = %PeerData{}
    peer = {id, data}
    case :ets.insert_new(swarm, peer) do
      true -> {:ok, data}
      false -> {:error, "peer already exists"}
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

  # get the total number of peers registered in the specified swarm
  def get_peer_count(swarm) do
    :ets.info(swarm, :size)
  end

  # get the total number of leechers registered in the specified swarm
  def get_leecher_count(swarm) do
    get_leechers(swarm, :infinity, false) |> length()
  end

  # get the total number of seeders registered in the specified swarm
  def get_seeder_count(swarm) do
    get_seeders(swarm, :infinity, false) |> length()
  end

  # return a list of all the peers registered in the swarm  up to 'count', optionally includes their associated data
  def get_peers(swarm, :infinity, true), do: :ets.match(swarm, :"$1")
  def get_peers(swarm, :infinity, false), do: :ets.match(swarm, {:"$1", :_})
  def get_peers(swarm, count, true), do: :ets.match(swarm, :"$1", count)
  def get_peers(swarm, count, false), do: :ets.match(swarm, {:"$1", :_}, count)

  def get_leechers(swarm, :infinity, true) do
    #spec = :ets.fun2ms(fn {id, data} = peer when data.left > 0 -> peer end)
    spec = [{{:"$1", :"$2"}, [{:>, {:map_get, :left, :"$2"}, 0}], [:"$_"]}]
    :ets.select(swarm, spec)
  end

  def get_leechers(swarm, count, true) do
    #spec = :ets.fun2ms(fn {id, data} = peer when data.left > 0 -> peer end)
    spec = [{{:"$1", :"$2"}, [{:>, {:map_get, :left, :"$2"}, 0}], [:"$_"]}]
    :ets.select(swarm, spec, count)
  end

  def get_leechers(swarm, :infinity, false) do
    #spec = :ets.fun2ms(fn {id, data} when data.left > 0 -> id end)
    spec = [{{:"$1", :"$2"}, [{:>, {:map_get, :left, :"$2"}, 0}], [:"$1"]}]
    :ets.select(swarm, spec)
  end

  def get_leechers(swarm, count, false) do
    #spec = :ets.fun2ms(fn {id, data} when data.left > 0 -> id end)
    spec = [{{:"$1", :"$2"}, [{:>, {:map_get, :left, :"$2"}, 0}], [:"$1"]}]
    :ets.select(swarm, spec, count)
  end

  def get_seeders(swarm, :infinity, true) do
    #spec = :ets.fun2ms(fn {id, data} = peer when data.left == 0 -> peer end)
    spec = [{{:"$1", :"$2"}, [{:==, {:map_get, :left, :"$2"}, 0}], [:"$_"]}]
    :ets.select(swarm, spec)
  end

  def get_seeders(swarm, count, true) do
    #spec = :ets.fun2ms(fn {id, data} = peer when data.left == 0 -> peer end)
    spec = [{{:"$1", :"$2"}, [{:==, {:map_get, :left, :"$2"}, 0}], [:"$_"]}]
    :ets.select(swarm, spec, count)
  end

  def get_seeders(swarm, :infinity, false) do
    #spec = :ets.fun2ms(fn {id, data} when data.left == 0 -> id end)
    spec = [{{:"$1", :"$2"}, [{:==, {:map_get, :left, :"$2"}, 0}], [:"$1"]}]
    :ets.select(swarm, spec)
  end

  def get_seeders(swarm, count, false) do
    #spec = :ets.fun2ms(fn {id, data} when data.left == 0 -> id end)
    spec = [{{:"$1", :"$2"}, [{:==, {:map_get, :left, :"$2"}, 0}], [:"$1"]}]
    :ets.select(swarm, spec, count)
  end
end
