defmodule ExTracker.Processors.Scrape do

  import ExTracker.Utils
  alias ExTracker.Types.ScrapeResponse
  alias ExTracker.Types.ScrapeRequest

  # entrypoint for client's "/scrape" requests
  def process(source_ip, params) do
    # TODO scrapes are supposed to allow multiple 'info_hash' keys to be present to scrape more than one torrent at a time
    # but apparently the standard requires those keys to have '[]' appended to be treated as a list, otherwise they get overwritten
    # this probably needs a custom query_string parser at the router level
    case ScrapeRequest.parse(params) do
      {:ok, request} ->
        with {:ok, swarm} <- get_swarm(request.info_hash), # find swarm based on info_hash
        {:ok, seeders} <- get_total_seeders(swarm), # get number of seeders for this swarm
        {:ok, leechers} <- get_total_leechers(swarm), # get number of leechers for this swarm
        {:ok, downloads} <- get_total_downloads(swarm) # get absolute number of downloads for this swarm
        do
          # bencoded response
          generate_success_response(seeders, leechers, downloads)
        else
          {:error, error} -> generate_failure_response(error)
          _ -> {500, "nope"}
        end
      {:error, error} ->
        generate_failure_response(error)
    end
  end

  defp get_swarm(hash) do
    case ExTracker.SwarmFinder.find(hash) do
      :error -> {:error, "torrent not found"}
      swarm -> {:ok, swarm}
    end
  end

  def get_total_seeders(swarm) do
    {:ok, ExTracker.Swarm.get_seeder_count(swarm)}
  end

  def get_total_leechers(swarm) do
    {:ok, ExTracker.Swarm.get_leecher_count(swarm)}
  end

  def get_total_downloads(swarm) do
    {:ok, 0} #TODO
  end

  defp generate_success_response(seeders, leechers, downloads) do
    response =
      ScrapeResponse.generate_success(seeders, leechers, downloads)
      |> Benx.encode()
    {200, response}
  end

  defp generate_failure_response(reason) do
    response =
      ScrapeResponse.generate_failure(reason)
      |> Benx.encode()
    {200, "#{response}"}
  end
end
