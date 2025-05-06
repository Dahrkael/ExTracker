defmodule ExTracker.Cmd do
  require Logger
  alias ExTracker.Types.PeerID

  def show_swarm_list(show_peers) do
    swarms = ExTracker.SwarmFinder.get_swarm_list()
    Enum.each(swarms, fn swarm ->
      {hash, table, timestamp} = swarm
      created = DateTime.from_unix!(timestamp, :millisecond)

      info = %{
        "hash" => String.downcase(Base.encode16(hash)),
        "created" => DateTime.to_string(created),
        "total_memory" => (:ets.info(table, :memory) * :erlang.system_info(:wordsize)),
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

  def show_swarm_total_memory() do
    swarms = ExTracker.SwarmFinder.get_swarm_list()
    memory = Enum.reduce(swarms, 0, fn swarm, acc ->
      {_hash, table, _created_at, _last_cleaned} = swarm
      usage = (:ets.info(table, :memory) * :erlang.system_info(:wordsize))
      acc + usage
    end)
    IO.inspect(memory, label: "Total memory used by swarms" )
    :ok
  end

  def show_pretty_swarm_list() do
    swarms = ExTracker.SwarmFinder.get_swarm_list()
    data = Enum.map(swarms, fn swarm ->
      {hash, table, timestamp} = swarm
      created = DateTime.from_unix!(timestamp, :millisecond)

      %{
        "hash" => String.downcase(Base.encode16(hash)),
        "created" => DateTime.to_string(created),
        "total_memory" => (:ets.info(table, :memory) * :erlang.system_info(:wordsize)),
        "peer_count" => ExTracker.Swarm.get_peer_count(table)
      }
    end)
    SwarmPrintout.print_table(data)
    :ok

  end

  def show_swarm_info(info_hash) do
    with {:ok, hash} <- ExTracker.Utils.validate_hash(info_hash),
      {:ok, swarm} <- get_swarm(hash)
      do
        memory = :ets.info(swarm, :memory) * :erlang.system_info(:wordsize)
        peers = ExTracker.Swarm.get_peers(swarm, :infinity, false)
        info = %{
          "swarm" => String.downcase(Base.encode16(hash)),
          "total_memory" => memory,
          "peer_memory" => (memory / :ets.info(swarm, :size)),
          "peers" => peers
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
      total + (ExTracker.Swarm.get_leechers(table, :infinity, false) |> length())
    end)
    IO.inspect(seeder_total, label: "Total seeders")
    :ok
  end

  def show_seeder_count() do
    swarms = ExTracker.SwarmFinder.get_swarm_list()
    seeder_total = Enum.reduce(swarms, 0, fn swarm, total ->
      {_hash, table, _timestamp} = swarm
      total + (ExTracker.Swarm.get_seeders(table, :infinity, false) |> length())
    end)
    IO.inspect(seeder_total, label: "Total seeders")
    :ok
  end

  def create_fake_swarms(swarm_count, peer_count) do
    start = System.monotonic_time(:millisecond)
    Enum.map(1..swarm_count, fn _s ->
      # create random hash
      hash = :crypto.strong_rand_bytes(20)
      # create swarm
      swarm = ExTracker.SwarmFinder.find_or_create(hash)
      # fill it with fake peers
      Enum.map(1..peer_count, fn _p ->
        # create random peer data
        <<a, b, c, d>> = :crypto.strong_rand_bytes(4)
        ip = {a, b, c, d}
        port = Enum.random(1024..65535)
        # add the peers
        ExTracker.Swarm.add_peer(swarm, PeerID.new(ip, port))
      end)
    end)
    finish = System.monotonic_time(:millisecond)
    Logger.debug("created #{swarm_count} fake swarms with #{peer_count} fake peers each in #{finish - start}ms")
  end
end
