defmodule ExTracker.Cmd do
  require Logger
  alias ExTracker.Types.PeerID

  def shutdown() do
    # make a back up before shutting down
    if Application.get_env(:extracker, :backup_auto_enabled) do
      Application.get_env(:extracker, :backup_auto_path) |> ExTracker.Backup.make_sync()
    end

    Logger.critical("shutting down!")
    System.stop(0)
  end

  def show_swarm_list(show_peers) do
    swarms = ExTracker.SwarmFinder.get_swarm_list()
    Enum.each(swarms, fn swarm ->
      {hash, table, created_at, _last_cleaned} = swarm
      created = DateTime.from_unix!(created_at, :millisecond)

      info = %{
        "hash" => String.downcase(Base.encode16(hash)),
        "created" => DateTime.to_string(created),
        "total_memory" => (:ets.info(table, :memory) * :erlang.system_info(:wordsize)),
      }

      info = case show_peers do
        true -> Map.put(info, "peers", ExTracker.Swarm.get_all_peers(table, false))
        false-> Map.put(info, "peer_count", ExTracker.Swarm.get_peer_count(table))
      end

      IO.inspect(info, label: "Swarm", limit: :infinity )
    end)
    :ok
  end

  def show_biggest_swarms(count) do
    ExTracker.SwarmFinder.get_swarm_list()
      |> Task.async_stream(fn {hash, table, created_at, _last_cleaned} ->
        {hash, table, created_at, ExTracker.Swarm.get_peer_count(table)}
      end, ordered: false)
      |> Stream.filter(&match?({:ok, _}, &1))
      |> Enum.map(&elem(&1, 1))
      |> Enum.sort_by(&elem(&1, 3), :desc) # order by peer count
      |> Enum.take(count)
      |> Task.async_stream(fn{hash, table, created_at, peer_count} ->
        created = DateTime.from_unix!(created_at, :millisecond)
        %{
          "hash" => String.downcase(Base.encode16(hash)),
          "created" => DateTime.to_string(created),
          "total_memory" => (:ets.info(table, :memory) * :erlang.system_info(:wordsize)),
          "peer_count" => peer_count
        }
      end, ordered: false)
      |> Stream.filter(&match?({:ok, _}, &1))
      |> Enum.map(&elem(&1, 1))
      |> SwarmPrintout.print_table()
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
    data =
      ExTracker.SwarmFinder.get_swarm_list()
      |> Task.async_stream(fn swarm ->
        {hash, table, created_at, _last_cleaned} = swarm
        created = DateTime.from_unix!(created_at, :millisecond)

        %{
          "hash" => String.downcase(Base.encode16(hash)),
          "created" => DateTime.to_string(created),
          "total_memory" => (:ets.info(table, :memory) * :erlang.system_info(:wordsize)),
          "peer_count" => ExTracker.Swarm.get_peer_count(table)
        }

      end, ordered: false)
      |> Stream.filter(&match?({:ok, _}, &1))
      |> Enum.map(&elem(&1, 1))

    SwarmPrintout.print_table(data)
    :ok
  end

  def show_swarm_info(info_hash) do
    with {:ok, hash} <- ExTracker.Utils.validate_hash(info_hash),
      {:ok, swarm} <- get_swarm(hash)
      do
        memory = :ets.info(swarm, :memory) * :erlang.system_info(:wordsize)

        info = %{
          "swarm" => String.downcase(Base.encode16(hash)),
          "total_memory" => memory,
          "peer_memory" => (memory / :ets.info(swarm, :size)),
          "peers" => %{
            "all" => %{
              "count" => ExTracker.Swarm.get_peer_count(swarm),
              "total" => ExTracker.Swarm.get_peer_count(swarm, :all),
              "leechers" => ExTracker.Swarm.get_seeder_count(swarm, :all),
              "seeders" => ExTracker.Swarm.get_leecher_count(swarm, :all)
            },
            "ipv4" => %{
              "total" => ExTracker.Swarm.get_peer_count(swarm, :inet),
              "leechers" => ExTracker.Swarm.get_leecher_count(swarm, :inet),
              "seeders" => ExTracker.Swarm.get_seeder_count(swarm, :inet)
            },
            "ipv6" => %{
              "total" => ExTracker.Swarm.get_peer_count(swarm, :inet6),
              "leechers" => ExTracker.Swarm.get_leecher_count(swarm, :inet6),
              "seeders" => ExTracker.Swarm.get_seeder_count(swarm, :inet6)
            },
          }
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

  def show_peer_count(family) do
    total = ExTracker.SwarmFinder.get_swarm_list()
    |> Task.async_stream(fn {_hash, table, _created_at, _last_cleaned} ->
      ExTracker.Swarm.get_peer_count(table, family)
    end, ordered: false)
    |> Stream.reject(&match?({_, :undefined}, &1))
    |> Stream.map(&elem(&1, 1))
    |> Enum.sum()

    IO.inspect(total, label: "Total peers (family: #{to_string(family)})")
    :ok
  end

  def show_leecher_count(family) do
    total = ExTracker.SwarmFinder.get_swarm_list()
    |> Task.async_stream(fn {_hash, table, _created_at, _last_cleaned} ->
      ExTracker.Swarm.get_leecher_count(table, family)
    end, ordered: false)
    |> Stream.reject(&match?({_, :undefined}, &1))
    |> Stream.map(&elem(&1, 1))
    |> Enum.sum()

    IO.inspect(total, label: "Total leechers (family: #{to_string(family)})")
    :ok
  end

  def show_seeder_count(family) do
    total = ExTracker.SwarmFinder.get_swarm_list()
    |> Task.async_stream(fn {_hash, table, _created_at, _last_cleaned} ->
      ExTracker.Swarm.get_seeder_count(table, family)
    end, ordered: false)
    |> Stream.reject(&match?({_, :undefined}, &1))
    |> Stream.map(&elem(&1, 1))
    |> Enum.sum()

    IO.inspect(total, label: "Total seeders (family: #{to_string(family)})")
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
