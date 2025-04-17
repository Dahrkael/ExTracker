defmodule ExTracker.Utils do

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
