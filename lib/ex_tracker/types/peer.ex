defmodule ExTracker.Types.PeerID do
  alias ExTracker.Types.PeerID

  @enforce_keys [:ip, :port, :family]
  defstruct [:ip, :port, :family]

  def new(ip, port) do
    family = cond do
      tuple_size(ip) == 4 -> :inet
      tuple_size(ip) == 8 -> :inet6
    end

    %PeerID{ip: ip, port: port, family: family}
  end

  def is_ipv4(%PeerID{family: family}) do
    family == :inet
  end

  def is_ipv6(%PeerID{family: family}) do
    family == :inet6
  end
end

defimpl String.Chars, for: ExTracker.Types.PeerID do
  def to_string(%ExTracker.Types.PeerID{ip: ip, port: port}) do
    ip_str = ip |> Tuple.to_list() |> Enum.join(".")
    "#{ip_str}:#{port}"
  end
end

defmodule ExTracker.Types.PeerData do
  alias ExTracker.Types.PeerData

  defstruct [
    id: nil,
    key: nil,
    uploaded: 0,
    downloaded: 0,
    left: 0,
    country: "",
    last_event: nil,
    last_updated: 0
  ]

  def set_id(peer_data, id) when byte_size(id) == 20 do
    %PeerData{peer_data | id: id}
  end

  def validate_key(peer_data, key) do
      cond do
        peer_data.key == nil -> true
        peer_data.key == key -> true
        true -> false
      end
  end

  def set_key(peer_data, new_key) do
    cond do
      peer_data.key == nil -> %PeerData{peer_data | key: new_key}
      peer_data.key == new_key -> peer_data
      true -> {:error, "different key already set"}
    end
  end

  def update_uploaded(peer_data, value) when is_integer(value) do
    case peer_data.uploaded < value do
      true -> %PeerData{peer_data | uploaded: value}
      false -> peer_data
    end
  end

  def update_downloaded(peer_data, value) when is_integer(value) do
    case peer_data.downloaded < value do
      true -> %PeerData{peer_data | downloaded: value}
      false -> peer_data
    end
  end

  def update_left(peer_data, value) when is_integer(value) do
    %PeerData{peer_data | left: value}
  end

  def update_country(peer_data, country) when is_binary(country) do
    %PeerData{peer_data | country: country}
  end

  def update_last_event(peer_data, event) when is_atom(event) do
    %PeerData{peer_data | last_event: event}
  end

  def update_last_updated(peer_data, timestamp) do
    %PeerData{peer_data | last_updated: timestamp}
  end
end
