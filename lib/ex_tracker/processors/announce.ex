defmodule ExTracker.Processors.Announce do

  import ExTracker.Utils
  require Logger
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
          :ok <- early_out_on_stopped(client, swarm, event), # stop processing right here if the peer stopped
          {:ok, peer_data} <- get_peer(swarm, client), # retrieve or create peer data
          :ok <- check_announce_interval(client, peer_data), # is the peer respecting the provided intervals?
          {:ok, peer_data} <- update_stats(swarm, client, peer_data, request), # update peer stats
          {:ok, peer_list} <- generate_peer_list(swarm, client, peer_data, event, request), # generate peer list
          {:ok, totals} <- get_total_peers(swarm) # get number of seeders and leechers for this swarm
        do
          generate_success_response(peer_list, totals, source_ip)
        else
          {:error, error} ->
            Logger.warning("peer #{client} received an error: #{error}")
            generate_failure_response(error)
          _ -> {:error, "unknown internal error"}
        end
      {:error, error} ->
        Logger.warning("peer #{inspect(source_ip)} sent an invalid announce: #{error}")
        generate_failure_response(error)
    end
  end

  defp process_event(event) do
    case event do
      :invalid -> {:error, "invalid event"}
      _ -> {:ok, event}
    end
  end

  defp get_swarm(hash) do
    swarm = ExTracker.SwarmFinder.find_or_create(hash)
    {:ok, swarm}
  end

  defp early_out_on_stopped(client, swarm, event) do
    # the peer is not coming back so just remove it and exit, it doesnt need peers
    if event == :stopped do
      ExTracker.Swarm.remove_peer(swarm, client)
      exit(:normal)
    end
    :ok
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

  defp check_announce_interval(client, peer_data) do
    if peer_data.state != :fresh do
      now = System.system_time(:millisecond)
      elapsed = now - peer_data.last_updated
      elapsed = elapsed + 1000 # some clients like to announce a few milliseconds early so give it some wiggle
      cond do
        elapsed < (Application.get_env(:extracker, :announce_interval_min) * 1000) ->
          {:error, "didn't respect minimal announcement interval"}
        elapsed < (Application.get_env(:extracker, :announce_interval) * 1000) ->
          Logger.warning("peer #{client} is announcing too soon (#{elapsed / 1000} seconds since last time)")
          # TODO should we take an automatic action in this case?
          :ok
        true ->
          :ok
      end
    else
      :ok
    end
  end

  defp update_stats(swarm, client, peer_data, request) do
    updated_data = peer_data
      |> PeerData.set_id(request.peer_id)
      #|> PeerData.set_key(request.key)
      |> PeerData.update_uploaded(request.uploaded)
      |> PeerData.update_downloaded(request.downloaded)
      |> PeerData.update_left(request.left)

    # TODO increase swarm downloads counter if 'left' reaches zero
    if peer_data.left > 0 && request.left == 0 do
    end

    # update peer internal state based on the provided event
    updated_data =
      case request.event do
        :started -> PeerData.update_state(updated_data, :active)
        :stopped -> PeerData.update_state(updated_data, :gone)
        :updated -> PeerData.update_state(updated_data, :active)
        :completed -> PeerData.update_state(updated_data, :active)
      end

      if updated_data.state == :gone do
        # remove the peer as it has abandoned the swarm
        ExTracker.Swarm.remove_peer(swarm, client)
      else
        # update the peer info in the swarm
        ExTracker.Swarm.update_peer(swarm, client, updated_data)
      end
      {:ok, updated_data}
  end

  # the stopped event mean the peer is done with the torrent so it doesn't need more peers
  defp generate_peer_list(_swarm, _client, _peer_data, :stopped, _request), do: {:ok, []}

  defp generate_peer_list(swarm, _client, peer_data, _event, request) do
    need_peer_data = !request.compact
    max_peers = Application.get_env(:extracker, :max_peers_returned, 25)
    desired_total = if request.numwant > max_peers or request.numwant < 0, do: max_peers, else: request.numwant

    peer_list = case peer_data.left do
      0 ->
        # peer is seeding so try to give it leechers
        leechers = ExTracker.Swarm.get_leechers(swarm, :infinity, need_peer_data)
        case length(leechers) do
          length when length == desired_total ->
            # if theres just enough peers to fill the list that's great
            leechers
          length when length > desired_total ->
            # if there are more peers than requested then take a random subset
            Enum.take_random(leechers, desired_total)
          length when length < desired_total ->
            # there are not enough leechers so try to fill up with some random seeders
            ExTracker.Swarm.get_seeders(swarm, :infinity, need_peer_data) |> Enum.take_random(desired_total - length)
        end
      _ ->
        # peer is leeching so try to give it seeders
        seeders = ExTracker.Swarm.get_seeders(swarm, :infinity, need_peer_data)
        case length(seeders) do
          length when length == desired_total ->
            # if theres just enough peers to fill the list that's great
            seeders
          length when length > desired_total ->
            # if there are more peers than requested then take a random subset
            Enum.take_random(seeders, desired_total)
          length when length < desired_total ->
            # there are not enough seeders so try to fill up with some random leechers
            ExTracker.Swarm.get_leechers(swarm, :infinity, need_peer_data) |> Enum.take_random(desired_total - length)
        end
    end

    # convert the peers to the expected representation for delivery
    peer_list = Enum.map(peer_list, fn peer ->
        case request.compact do
          true -> ipv4_to_bytes(peer.ip) <> port_to_bytes(peer.port)
          false ->
            {id, data} = peer
            result = %{"ip" => id.ip, "port" => id.port}
            if request.no_peer_id == false do
              Map.put(result, "peer id", data.id)
            end
            result
        end
      end)

    case request.compact do
      true -> {:ok, IO.iodata_to_binary(peer_list)}
      false -> {:ok, peer_list}
    end
  end

  defp get_total_peers(swarm) do
    seeders = ExTracker.Swarm.get_seeder_count(swarm)
    leechers = ExTracker.Swarm.get_leecher_count(swarm)
    {:ok, {seeders, leechers}}
  end

  defp generate_success_response(peer_list, totals, source_ip) do
    {total_seeders, total_leechers} = totals
    response =
      AnnounceResponse.generate_success(peer_list, total_seeders, total_leechers)
      |> AnnounceResponse.append_external_ip(source_ip)
    {:ok, response}
  end

  defp generate_failure_response(reason) do
    response = AnnounceResponse.generate_failure(reason)
    {:error, response}
  end
end
