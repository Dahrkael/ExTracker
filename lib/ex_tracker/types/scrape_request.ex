defmodule ExTracker.Types.ScrapeRequest do

  def parse(params) do
    # mandatory fields
    with {:ok, info_hash} <- fetch_field_info_hash(params)
    do
      request = %{ info_hash: info_hash }
      {:ok, request}
    else
      {:error, message} -> {:error, message}
      _ -> {:error, "unknown error"}
    end
  end

  #==========================================================================
  # Mandatory Fields
  #==========================================================================

  # info_hash: urlencoded 20-byte SHA1 hash of the value of the info key from the Metainfo file.
  defp fetch_field_info_hash(params) do
    case Map.fetch(params, "info_hash") do
      {:ok, info_hash} ->
        case ExTracker.Utils.validate_hash(info_hash) do
          {:ok, decoded_hash} -> {:ok, decoded_hash}
          {:error, error} -> {:error, "invalid 'info_hash' parameter: #{error}"}
        end
      :error -> {:error, "missing 'info_hash' parameter"}
    end
  end
end
