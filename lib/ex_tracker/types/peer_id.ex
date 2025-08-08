defmodule ExTracker.Types.PeerID do
  @moduledoc """
  Runtime representation of a Peer ID for easy manipulation in code
  """

  alias ExTracker.Types.PeerID

  @enforce_keys [:ip, :port, :family]
  defstruct [:ip, :port, :family]

  def new(ip, port) when is_tuple(ip) and is_integer(port)do
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
  def to_string(%ExTracker.Types.PeerID{family: :inet, ip: ip, port: port}) do
    ip_str = ip |> Tuple.to_list() |> Enum.join(".")
    "#{ip_str}:#{port}"
  end

  def to_string(%ExTracker.Types.PeerID{family: :inet6, ip: ip, port: port}) do
    ip_str = ip |> Tuple.to_list() |> Enum.map(&String.pad_leading(Integer.to_string(&1, 16), 4, "0")) |> Enum.join(":") |> String.downcase() |> then(&"[#{&1}]")
    "#{ip_str}:#{port}"
  end
end

defmodule ExTracker.Types.PeerID.Storage do
  @moduledoc """
  Compact representation of a Peer ID targeted at saving space in ETS

  Format:
    · IPv4 → <<0x04, byte1, byte2, byte3, byte4, port::16>>
    · IPv6 → <<0x06, h1::16, h2::16, h3::16, h4::16,
               h5::16, h6::16, h7::16, h8::16, port::16>>
  """

  alias ExTracker.Types.PeerID

  @ipv4_tag 0x04
  @ipv6_tag 0x06

  @spec encode(PeerID.t()) :: binary()
  def encode(%PeerID{family: :inet, ip: {a, b, c, d}, port: port}) do
    <<@ipv4_tag, a, b, c, d, port::16>>
  end

  def encode(%PeerID{family: :inet6, ip: {h1, h2, h3, h4, h5, h6, h7, h8}, port: port}) do
    <<@ipv6_tag,
      h1::16, h2::16, h3::16, h4::16,
      h5::16, h6::16, h7::16, h8::16,
      port::16>>
  end

  @spec decode(binary()) :: PeerID.t()
  def decode(<<@ipv4_tag, a, b, c, d, port::16>>) do
    %PeerID{family: :inet, ip: {a, b, c, d}, port: port}
  end

  def decode(<<@ipv6_tag, rest::binary-size(16), port::16>>) do
    <<h1::16, h2::16, h3::16, h4::16,
      h5::16, h6::16, h7::16, h8::16>> = rest

    %PeerID{family: :inet6, ip: {h1, h2, h3, h4, h5, h6, h7, h8}, port: port}
  end
end
