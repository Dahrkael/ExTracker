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

  def get_peers(swarm, count) do
    :ets.match(swarm, "$1", count)
  end

  def get_peers(swarm) do
    :ets.tab2list(swarm)
  end

  def get_peer_count(swarm) do
    :ets.tab2list(swarm) |> length()
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
