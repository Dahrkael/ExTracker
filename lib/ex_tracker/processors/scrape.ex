defmodule ExTracker.Processors.Scrape do

  alias ExTracker.Types.ScrapeResponse
  alias ExTracker.Types.ScrapeRequest

  # entrypoint for client's "/scrape" requests
  def process(source_ip, params) do
    case ScrapeRequest.parse(params) do
      {:ok, request} ->
        with {:ok, swarm} <- get_swarm(request.info_hash), # find swarm based on info_hash
        {:ok, seeders} <- get_total_seeders(swarm), # get number of seeders for this swarm
        {:ok, leechers} <- get_total_leechers(swarm), # get number of leechers for this swarm
        {:ok, downloads} <- get_total_downloads(swarm) # get absolute number of downloads for this swarm
        do
          generate_success_response(seeders, leechers, downloads)
        else
          {:error, error} -> generate_failure_response(error)
          _ -> {:error, "unknown internal error"}
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
    response = ScrapeResponse.generate_success(seeders, leechers, downloads)
    {:ok, response}
  end

  defp generate_failure_response(reason) do
    response = ScrapeResponse.generate_failure(reason)
    {:error, response}
  end
end
