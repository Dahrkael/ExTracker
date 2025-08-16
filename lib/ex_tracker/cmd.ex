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
      created_at = ExTracker.SwarmFinder.get_swarm_creation_date(swarm.hash)
      created = DateTime.from_unix!(created_at, :millisecond)

      info = %{
        "hash" => String.downcase(Base.encode16(swarm.hash)),
        "created" => DateTime.to_string(created),
        "type" => Atom.to_string(swarm.type)
      }

      info = case show_peers do
        true -> Map.put(info, "peers", ExTracker.Swarm.get_all_peers(swarm, false))
        false-> Map.put(info, "peer_count", ExTracker.Swarm.get_all_peer_count(swarm, :all))
      end

      IO.inspect(info, label: "Swarm", limit: :infinity )
    end)
    :ok
  end

  def show_biggest_swarms(count) do
    ExTracker.SwarmFinder.get_swarm_list()
      |> Task.async_stream(fn swarm ->
        created_at = ExTracker.SwarmFinder.get_swarm_creation_date(swarm.hash)
        {swarm.hash, created_at, ExTracker.Swarm.get_all_peer_count(swarm, :all)}
      end, ordered: false)
      |> Stream.filter(&match?({:ok, _}, &1))
      |> Enum.map(&elem(&1, 1))
      |> Enum.sort_by(&elem(&1, 2), :desc) # order by peer count
      |> Enum.take(count)
      |> Task.async_stream(fn{hash, created_at, peer_count} ->
        created = DateTime.from_unix!(created_at, :millisecond)
        %{
          "hash" => String.downcase(Base.encode16(hash)),
          "created" => DateTime.to_string(created),
          "peer_count" => peer_count
        }
      end, ordered: false)
      |> Stream.filter(&match?({:ok, _}, &1))
      |> Enum.map(&elem(&1, 1))
      |> SwarmPrintout.print_table()
    :ok
  end

  def show_peer_count_stats() do
    counts =
      ExTracker.SwarmFinder.get_swarm_list()
      |> Task.async_stream(fn swarm ->
        ExTracker.Swarm.get_all_peer_count(swarm, :all)
      end,
        ordered: false,
        max_concurrency: System.schedulers_online() * 2)
      |> Stream.filter(&match?({:ok, _}, &1))
      |> Enum.map(&elem(&1, 1))

    n = length(counts)
    if n > 0 do
      min = Enum.min(counts)
      max = Enum.max(counts)
      mean = Enum.sum(counts) / n

      {mode, mode_freq} =
        counts
        |> Enum.frequencies()
        |> Enum.max_by(fn {_k, v} -> v end)

      dist = peer_count_distribution(counts)

      IO.puts("Peers per swarm (#{n} swarms):")
      IO.puts("  - Mean: #{Float.round(mean, 2)}")
      IO.puts("  - Mode/Freq: #{mode} / #{mode_freq}")
      IO.puts("  - Min/Max: #{min} / #{max}")
      IO.puts("  - Distribution:")
      Enum.each(dist, fn {label, c} ->
        IO.puts("      #{String.pad_trailing(label, 10)} #{c}")
      end)
    end
  end

  defp peer_count_distribution(counts) do
    distribution = [
      {0, 0},
      {1, 10},
      {11, 50},
      {51, 100},
      {101, 200},
      {201, 300},
      {301, 400},
      {401, 500},
      {501, 1000},
      {1001, 5000},
      {5001, :infinity}
    ]

    init = Map.from_keys(distribution, 0)
    result =
      counts
      |> Enum.reduce(init, fn count, acc ->
        bucket = Enum.find_value(distribution, fn
          {min, :infinity} -> if count >= min, do: {min, :infinity}
          {min, max} -> if count >= min and count <= max, do: {min, max}
        end)
        Map.update!(acc, bucket, &(&1 + 1))
      end)
      |> Enum.map(fn {bucket, total} ->
        label = case bucket do
          {a, :infinity} -> "#{a}+"
          {a, b} when a == b -> "#{a} "
          {a, b} -> "#{a}-#{b}"
        end
        {label, total}
      end)

    result
  end

  def show_swarm_count() do
    count = ExTracker.SwarmFinder.get_swarm_count()
    IO.inspect(count, label: "Registered swarm count")
    :ok
  end

  def show_pretty_swarm_list() do
    data =
      ExTracker.SwarmFinder.get_swarm_list()
      |> Task.async_stream(fn swarm ->
        created_at = ExTracker.SwarmFinder.get_swarm_creation_date(swarm.hash)
        created = DateTime.from_unix!(created_at, :millisecond)

        %{
          "hash" => String.downcase(Base.encode16(swarm.hash)),
          "created" => DateTime.to_string(created),
          "peer_count" => ExTracker.Swarm.get_all_peer_count(swarm, :all)
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
        info = %{
          "swarm" => String.downcase(Base.encode16(hash)),
          "peers" => %{
            "all" => %{
              "total" => ExTracker.Swarm.get_all_peer_count(swarm, :all),
              "leechers" => ExTracker.Swarm.get_seeder_count(swarm, :all),
              "seeders" => ExTracker.Swarm.get_leecher_count(swarm, :all)
            },
            "ipv4" => %{
              "total" => ExTracker.Swarm.get_all_peer_count(swarm, :inet),
              "leechers" => ExTracker.Swarm.get_leecher_count(swarm, :inet),
              "seeders" => ExTracker.Swarm.get_seeder_count(swarm, :inet)
            },
            "ipv6" => %{
              "total" => ExTracker.Swarm.get_all_peer_count(swarm, :inet6),
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
    |> Task.async_stream(fn swarm ->
      ExTracker.Swarm.get_all_peer_count(swarm, family)
    end, ordered: false)
    |> Stream.reject(&match?({_, :undefined}, &1))
    |> Stream.map(&elem(&1, 1))
    |> Enum.sum()

    IO.inspect(total, label: "Total peers (family: #{to_string(family)})")
    :ok
  end

  def show_leecher_count(family) do
    total = ExTracker.SwarmFinder.get_swarm_list()
    |> Task.async_stream(fn swarm ->
      ExTracker.Swarm.get_leecher_count(swarm, family)
    end, ordered: false)
    |> Stream.reject(&match?({_, :undefined}, &1))
    |> Stream.map(&elem(&1, 1))
    |> Enum.sum()

    IO.inspect(total, label: "Total leechers (family: #{to_string(family)})")
    :ok
  end

  def show_seeder_count(family) do
    total = ExTracker.SwarmFinder.get_swarm_list()
    |> Task.async_stream(fn swarm ->
      ExTracker.Swarm.get_seeder_count(swarm, family)
    end, ordered: false)
    |> Stream.reject(&match?({_, :undefined}, &1))
    |> Stream.map(&elem(&1, 1))
    |> Enum.sum()

    IO.inspect(total, label: "Total seeders (family: #{to_string(family)})")
    :ok
  end

  def show_countries() do
    countries =
      ExTracker.SwarmFinder.get_swarm_list()
      |> Task.async_stream(fn swarm ->
        ExTracker.Swarm.get_all_peers(swarm, true)
      end, ordered: false)
      |> Stream.reject(&match?({_, :undefined}, &1))
      |> Stream.map(&elem(&1, 1))
      |> Stream.map(fn peers -> # each swarm returns a list of its peers
        Enum.map(peers, fn {id, data} ->
          {id.family, data.country}
        end)
      end)
      |> Enum.to_list()
      |> List.flatten()
      |> Enum.group_by(fn {_family, country} -> country end)
      |> Enum.map(fn {country, peers} ->
        {
          country,
          length(peers),
          peers
          |> Enum.group_by(fn {family, _country} -> family end)
          |> Enum.map(fn {family, peers} -> {family, length(peers)} end)
        }
      end)
      |> Enum.sort_by(fn {_country, sum, _families} -> sum end, :desc)

    IO.inspect(countries, label: "Peers by country", limit: :infinity)
    :ok
  end

  def create_fake_swarms(swarm_count, peer_count) do
    start = System.monotonic_time(:millisecond)
    Task.async_stream(1..swarm_count, fn _s ->
      # create random hash
      hash = :crypto.strong_rand_bytes(20)
      # create swarm
      {:ok, swarm} = ExTracker.SwarmFinder.find_or_create(hash)
      # fill it with fake peers
      Enum.map(1..peer_count, fn _p ->
        # create random peer data
        <<a, b, c, d>> = :crypto.strong_rand_bytes(4)
        ip = {a, b, c, d}
        port = Enum.random(1024..65535)
        # add the peers
        ExTracker.Swarm.add_peer(swarm, PeerID.new(ip, port))
      end)
    end,
      max_concurrency: System.schedulers_online() * 2,
      ordered: false)
    |> Stream.run()
    finish = System.monotonic_time(:millisecond)
    Logger.debug("created #{swarm_count} fake swarms with #{peer_count} fake peers each in #{finish - start}ms")
  end
end
