defmodule ExTracker.Types.AnnounceResponse do

  def generate_success(family, compact, peer_list, total_seeders, total_leechers) do
    response = %{
      #warning message: (new, optional) Similar to failure reason, but the response still gets processed normally. The warning message is shown just like an error.
      #interval: Interval in seconds that the client should wait between sending regular requests to the tracker.
      "interval" => Application.get_env(:extracker, :announce_interval),
      #tracker id: A string that the client should send back on its next announcements. If absent and a previous announce sent a tracker id, do not discard the old value; keep using it.
      #"tracker id" => "",
      #complete: number of peers with the entire file, i.e. seeders (integer)
      "complete" => total_seeders,
      #incomplete: number of non-seeder peers, aka "leechers" (integer)
      "incomplete" => total_leechers,
      #peers: (dictionary model) The value is a list of dictionaries, each with the following keys:
      #    peer id: peer's self-selected ID, as described above for the tracker request (string)
      #    ip: peer's IP address either IPv6 (hexed) or IPv4 (dotted quad) or DNS name (string)
      #    port: peer's port number (integer)
      #peers: (binary model) Instead of using the dictionary model described above, the peers value may be a string consisting of multiples of 6 bytes. First 4 bytes are the IP address and last 2 bytes are the port number. All in network (big endian) notation.
      "peers" => peer_list
    }

    case {compact, family} do
      # if its compact and ipv6 use 'peers6'
      {true, :inet6} -> Map.put(response, "peers6", peer_list)
      # in all other cases just use 'peers'
      {_, _} -> Map.put(response, "peers", peer_list)
    end

    #min interval: (optional) Minimum announce interval. If present clients must not reannounce more frequently than this.
    response = case Application.fetch_env(:extracker, :announce_interval_min) do
      {:ok, value}-> Map.put(response, "min interval", value)
      :error -> response
    end

    response
  end

  # BEP 24 'Tracker Returns External IP' extra field
  def append_external_ip(response, ip) do
    case Application.get_env(:extracker, :return_external_ip) do
      true -> Map.put(response, "external ip", ExTracker.Utils.ip_to_bytes(ip))
      _ -> response
    end
  end

  def generate_failure(reason) do
    text = cond do
      is_atom(reason) -> Atom.to_string(reason)
      true -> reason
    end

    %{ "failure reason" => text }
  end
end
