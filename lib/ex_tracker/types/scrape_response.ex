defmodule ExTracker.Types.ScrapeResponse do

  def generate_success(seeders, partial_seeders, leechers, downloads) do
    # The response to a successful request is a bencoded dictionary containing one key-value pair:
    # the key files with the value being a dictionary of the 20-byte string representation of an infohash paired with a dictionary of swarm metadata.
    # The fields found in the swarm metadata dictionary are as follows:
    %{
      # complete: The number of active peers that have completed downloading.
      "complete" => seeders,
      # incomplete: The number of active peers that have not completed downloading.
      "incomplete" => leechers,
      # downloaded: The number of peers that have ever completed downloading.
      "downloaded" => downloads,
      # downloaders: The number of active peers that have not completed downloading, not including partial seeds.
      "downloaders" => leechers - partial_seeders
    }
  end

  def generate_failure(reason) do
    text = cond do
      is_atom(reason) -> Atom.to_string(reason)
      true -> reason
    end

    %{ "failure reason" => text }
  end
end
