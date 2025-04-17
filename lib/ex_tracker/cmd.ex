defmodule ExTracker.Cmd do

  def swarm_info(info_hash) do
    with {:ok, hash} <- ExTracker.Utils.validate_hash(info_hash),
      {:ok, swarm} <- get_swarm(hash)
      do
        dump_swarm_info(swarm)
      end
  end

  defp get_swarm(hash) do
    case ExTracker.SwarmFinder.find(hash) do
      :error -> {:error, "swarm does not exist"}
      swarm -> {:ok, swarm}
    end
  end

  defp dump_swarm_info(swarm) do
    info = %{
      "swarm" => swarm,
      "peers" => ExTracker.Swarm.get_peers(swarm)
    }

    IO.inspect(info)
  end
end
