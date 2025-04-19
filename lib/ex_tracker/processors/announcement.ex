defmodule ExTracker.Processors.Announcement do

  import ExTracker.Utils
  alias ExTracker.Types.AnnounceResponse
  alias ExTracker.Types.AnnounceRequest
  alias ExTracker.Types.PeerID
  alias ExTracker.Types.PeerData

  # entrypoint for client's "/announce" requests
  def process(source_ip, params) do
    case AnnounceRequest.parse(params) do
      {:ok, request} ->
        client = PeerID.new(source_ip, request.port)

        with {:ok, event} <- process_event(request.event), # check event first as its the simplest
          {:ok, swarm} <- get_swarm(request.info_hash), # find swarm based on info_hash
          {:ok, peer_data} <- get_peer(swarm, client), # retrieve or create peer data
          {:ok, peer_data} <- update_stats(swarm, client, peer_data, event), # update peer stats
          {:ok, peer_list} <- generate_peer_list(swarm, client, peer_data, event, request) # generate peer list
        do
          # bencoded response
          generate_success_response(peer_list)
        else
          {:error, error} -> generate_failure_response(error)
          _ -> {500, "nope"}
        end
      {:error, error} ->
        generate_failure_response(error)
    end
  end

  defp get_swarm(hash) do
    swarm = ExTracker.SwarmFinder.find_or_create(hash)
    {:ok, swarm}
  end

  defp get_peer(swarm, client) do
    case ExTracker.Swarm.find_peer(swarm, client) do
      {:ok, data} ->
        {:ok, data}
      :notfound ->
        case ExTracker.Swarm.add_peer(swarm, client) do
          {:ok, data} -> {:ok, data}
           {:error, error} -> {:error, error}
        end
    end
  end

  defp process_event(event) do
    case event do
      :invalid -> {:error, "invalid  event"}
      _ -> {:ok, event}
    end
  end

  defp update_stats(swarm, client, peer_data, event) do
    {:ok, peer_data}
  end

  defp generate_peer_list(swarm, client, peer_data, event, request) do
    # TODO return leechers if its a seeder and viceversa
    desired_total = if request.numwant > 25, do: 25, else: request.numwant
    peer_list =
      ExTracker.Swarm.get_peers(swarm)
      |> Enum.take_random(desired_total)
      |> Enum.map(fn peer ->
        {id, data} = peer
        case request.compact do
          true -> ipv4_to_bytes(id.ip) <> port_to_bytes(id.port)
          false -> %{"peer id" => data.id, "ip" => id.ip, "port" => id.port}
        end
      end)

    case request.compact do
      true -> {:ok, IO.iodata_to_binary(peer_list)}
      false -> {:ok, peer_list}
    end
  end

  defp generate_success_response(peer_list) do
    response =
      AnnounceResponse.generate_success(peer_list)
      |> Benx.encode()
      |> IO.iodata_to_binary()
    {200, response}
  end

  defp generate_failure_response(reason) do
    response =
      AnnounceResponse.generate_failure(reason)
      |> Benx.encode()
    {200, "#{response}"}
  end
end
