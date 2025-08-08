defmodule ExTracker.Types.PeerID do
  @moduledoc """
  Runtime representation of a Peer ID for easy manipulation in code
  """

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
  def to_string(%ExTracker.Types.PeerID{family: :inet, ip: ip, port: port}) do
    ip_str = ip |> Tuple.to_list() |> Enum.join(".")
    "#{ip_str}:#{port}"
  end

  def to_string(%ExTracker.Types.PeerID{family: :inet6, ip: ip, port: port}) do
    ip_str = ip |> Tuple.to_list() |> Enum.map(&String.pad_leading(Integer.to_string(&1, 16), 4, "0")) |> Enum.join(":") |> String.downcase() |> then(&"[#{&1}]")
    "#{ip_str}:#{port}"
  end
end
