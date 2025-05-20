defmodule ExTracker.Utils do

  def pad_to_8_bytes(bin) when byte_size(bin) < 8 do
    padding = :binary.copy(<<0>>, 8 - byte_size(bin))
    padding <> bin
  end
  def pad_to_8_bytes(bin), do: bin

  def hash_to_string(hash) do
    String.downcase(Base.encode16(hash))
  end

  def ip_to_bytes(ip) when is_tuple(ip) and tuple_size(ip) == 4 do
    ip |> Tuple.to_list() |> :binary.list_to_bin()
  end

  def ip_to_bytes(ip) when is_tuple(ip) and tuple_size(ip) == 8 do
    ip |> Tuple.to_list() |> Enum.map(fn num -> <<num::16>> end) |> IO.iodata_to_binary()
  end

  def ipv4_to_bytes(ip) do
    ip |> String.split(".") |> Enum.map(&String.to_integer/1) |> :binary.list_to_bin()
  end

  def port_to_bytes(port) do
    <<port::16>>
  end

  def get_configured_ipv4() do
    {:ok, address} =
      Application.get_env(:extracker, :ipv4_bind_address)
      |> to_charlist()
      |> :inet.parse_ipv4_address()
      address
  end

  def get_configured_ipv6() do
    {:ok, address} =
      Application.get_env(:extracker, :ipv6_bind_address)
      |> to_charlist()
      |> :inet.parse_ipv6_address()
      address
  end

  # v1 hex-string hash (40 bytes, SHA-1)
  def validate_hash(hash) when is_binary(hash) and byte_size(hash) == 40 do
    with true <- String.valid?(hash, :fast_ascii),
    {:ok, decoded} <- Base.decode16(String.upcase(hash))
    do
      {:ok, decoded}
    else
      _ -> {:error, "invalid hex-string hash"}
    end
  end

  # v1 base32 hash (32 bytes)
  def validate_hash(hash) when is_binary(hash) and byte_size(hash) == 32 do
    case Base.decode32(hash, case: :upper) do
      {:ok, decoded} -> {:ok, decoded}
      :error -> {:error, "invalid base32 hash"}
    end
  end

  # v1 binary hash (20 bytes, SHA-1) or v2 truncated binary hash (32 bytes, SHA-256)
  def validate_hash(hash) when is_binary(hash) and byte_size(hash) == 20, do: {:ok, hash}
  def validate_hash(hash) when is_list(hash), do: hash |> :erlang.list_to_binary() |> validate_hash()
  def validate_hash(_hash), do: {:error, "invalid hash"}
end
