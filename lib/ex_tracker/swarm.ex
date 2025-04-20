defmodule ExTracker.Swarm do
  alias ExTracker.Types.PeerData

  @spec find_peer(swarm :: any(), id :: PeerID) :: {:ok, PeerData} | :notfound
  def find_peer(swarm, id) do
    case :ets.lookup(swarm, id) do
      [{_, data}] -> {:ok, data}
      _ -> :notfound
    end
  end

  @spec add_peer(swarm :: any(), id :: PeerID) :: {:ok, PeerData} | {:error, any()}
  def add_peer(swarm, id) do
    data = %PeerData{}
    peer = {id, data}
    case :ets.insert_new(swarm, peer) do
      true -> {:ok, data}
      false -> {:error, "peer already exists"}
    end
  end

  @spec remove_peer(swarm :: any(), id :: PeerID) :: :ok | :notfound
  def remove_peer(swarm, id) do
    with [{_, _data}] <- :ets.lookup(swarm, id),
         true <- :ets.delete(swarm, id) do
      :ok
    else
      _ -> :notfound
    end
  end


  # return a list of all the peers registered in the swarm  up to 'count', optionally includes their associated data
  def get_peers(swarm, :infinity, true), do: :ets.match(swarm, :"$1")
  def get_peers(swarm, :infinity, false), do: :ets.match(swarm, {:"$1", :_})
  def get_peers(swarm, count, true), do: :ets.match(swarm, :"$1", count)
  def get_peers(swarm, count, false), do: :ets.match(swarm, {:"$1", :_}, count)

  def get_peer_count(swarm) do
    :ets.tab2list(swarm) |> length()
  end

  def get_leechers(swarm) do
    #spec = :ets.fun2ms(fn {id, data} when data.left > 0 -> id end)
    spec = [{{:"$1", :"$2"}, [{:>, {:map_get, :left, :"$2"}, 0}], [:"$1"]}]
    :ets.select(swarm, spec)
  end

  def get_seeders(swarm) do
    #spec = :ets.fun2ms(fn {id, data} when data.left == 0 -> id end)
    spec = [{{:"$1", :"$2"}, [{:==, {:map_get, :left, :"$2"}, 0}], [:"$1"]}]
    :ets.select(swarm, spec)
  end

  #@impl true
  #def handle_call({:get, count}, _from, state) do
    # get at least 33% completes
  #  completes = Enum.take_random(state.complete, count / 3)
    # fill the rest with incompletes
  #  Enum.take_random(state.incomplete, (count / 3) * 2)
  #  {:reply, state, state}
  #end

  #@impl true
  #def handle_call(:scrape, _from, state) do
  #  response = {state.hash, Enum.count(state.complete), Enum.count(state.incomplete), state.downloaded}
  #  {:reply, response, state}
  #end
end
