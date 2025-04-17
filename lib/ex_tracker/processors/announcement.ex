defmodule ExTracker.Processors.Announcement do

  import ExTracker.Utils
  alias ExTracker.Types.AnnounceResponse
  alias ExTracker.Types.AnnounceRequest
  alias ExTracker.Types.PeerID
  alias ExTracker.Types.PeerData

  # entrypoint for client's "/announce" requests
  def process(source_ip, params) do
    request = struct!(AnnounceRequest, params)
    peer_id = PeerID.new(source_ip, request.port)

    with {:ok, hash} <- validate_hash(request.info_hash), # validate info_hash
      {:ok, event} <- process_event(request), # check event first as its the simplest
      {:ok, swarm} <- get_swarm(hash), # find swarm based on info_hash
      {:ok, peer_data} <- get_peer(swarm, peer_id), # retrieve or create peer data
      {:ok, peer_data} <- update_stats(swarm, peer_id, peer_data, event), # update peer stats
      {:ok, peer_list} <- generate_peer_list(swarm, peer_id, peer_data, event, request) # generate peer list
      do
        # bencoded response
        generate_success_response(peer_list)
      else
        {:unknownevent, event} -> {400, "invalid event: #{event}"}
        {:error, error} -> {500, "error: #{error}"}
        _ -> {500, "nope"}
      end
  end

  defp get_swarm(hash) do
    swarm = ExTracker.SwarmFinder.find(hash)
    {:ok, swarm}
  end

  defp get_peer(swarm, peer_id) do
    case ExTracker.Swarm.find_peer(swarm, peer_id) do
      {:ok, data} ->
        {:ok, data}
      :notfound ->
        # TODO add only if event contains 'started'
        case ExTracker.Swarm.add_peer(swarm, peer_id) do
          {:ok, data} -> {:ok, data}
           {:error, error} -> {:error, error}
        end
    end
  end

  defp process_event(request) do
    case Map.fetch(request, :event) do
      {:ok, "started"} -> {:ok, :started}
      {:ok, "stopped"} -> {:ok, :stopped}
      {:ok, "completed"} -> {:ok, :completed}
      :error -> {:ok, :updated} # event missing
      other -> {:unknownevent, other}
    end
  end

  defp update_stats(swarm, peer_id, peer_data, event) do

  end

  defp generate_peer_list(swarm, peer_id, peer_data, event, request) do
    # :stopped = 0
    # peer_data.left == 0 -> leeches || seeds
    desired_total = if request.numwant > 25, do: 25, else: request.numwant
  end

  defp generate_success_response(peer_list) do
    response =
      AnnounceResponse.generate_success(peer_list, false)
      |> Benx.encode()
    {200, "#{response}"}
  end

  defp generate_failure_response(reason) do
    response =
      AnnounceResponse.generate_failure(reason)
      |> Benx.encode()
    {200, "#{response}"}
  end
end
