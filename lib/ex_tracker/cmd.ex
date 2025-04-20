defmodule ExTracker.Cmd do

  def show_swarm_list(show_peers) do
    swarms = ExTracker.SwarmFinder.get_swarm_list()
    Enum.each(swarms, fn swarm ->
      {hash, table, timestamp} = swarm
      created = DateTime.from_unix!(timestamp, :millisecond)

      info = %{
        "hash" => String.downcase(Base.encode16(hash)),
        "created" => DateTime.to_string(created)
      }

      info = case show_peers do
        true -> Map.put(info, "peers", ExTracker.Swarm.get_peers(table, :infinity, false))
        false-> Map.put(info, "peer_count", ExTracker.Swarm.get_peer_count(table))
      end

      IO.inspect(info, label: "Swarm", limit: :infinity )
    end)
    :ok
  end

  def show_swarm_count() do
    count = ExTracker.SwarmFinder.get_swarm_count()
    IO.inspect(count, label: "Registered swarm count")
    :ok
  end

  def show_swarm_info(info_hash) do
    with {:ok, hash} <- ExTracker.Utils.validate_hash(info_hash),
      {:ok, swarm} <- get_swarm(hash)
      do
        info = %{
          "swarm" => Base.encode16(swarm),
          "peers" => ExTracker.Swarm.get_peers(swarm, :infinity, false)
        }

        IO.inspect(info)
      end
      :ok
  end

  defp get_swarm(hash) do
    case ExTracker.SwarmFinder.find(hash) do
      :error -> {:error, "swarm does not exist"}
      swarm -> {:ok, swarm}
    end
  end

  def show_peer_count() do
    swarms = ExTracker.SwarmFinder.get_swarm_list()
    seeder_total = Enum.reduce(swarms, 0, fn swarm, total ->
      {_hash, table, _timestamp} = swarm
      total + ExTracker.Swarm.get_peer_count(table)
    end)
    IO.inspect(seeder_total, label: "Total peers")
    :ok
  end

  def show_leecher_count() do
    swarms = ExTracker.SwarmFinder.get_swarm_list()
    seeder_total = Enum.reduce(swarms, 0, fn swarm, total ->
      {_hash, table, _timestamp} = swarm
      total + (ExTracker.Swarm.get_leechers(table) |> length())
    end)
    IO.inspect(seeder_total, label: "Total seeders")
    :ok
  end

  def show_seeder_count() do
    swarms = ExTracker.SwarmFinder.get_swarm_list()
    seeder_total = Enum.reduce(swarms, 0, fn swarm, total ->
      {_hash, table, _timestamp} = swarm
      total + (ExTracker.Swarm.get_seeders(table) |> length())
    end)
    IO.inspect(seeder_total, label: "Total seeders")
    :ok
  end
end
