defmodule ExTrackerTest.MemoryTest do
  use ExUnit.Case, async: false
  import Bitwise

  alias ExTracker.Types.PeerID
  alias ExTracker.Types.PeerID.Storage
  alias ExTracker.Types.PeerData

  @sizes [1, 1_000, 100_000]

  defp generate_fake_peer_ipv4(i) do
    # IP: 192.0.0.0 → 192.255.255.255 (24 bits)
    a = 192
    b = rem(i >>> 16, 256)
    c = rem(i >>> 8, 256)
    d = rem(i, 256)

    ip = {a, b, c, d}
    port = 1024 + rem(i, 64512)
    PeerID.new(ip, port)
  end

  defp generate_fake_peer_ipv6(i) do
    # fixed prefix 2001:db8:0:0
    h1 = 0x2001
    h2 = 0x0db8
    h3 = 0
    h4 = 0

    # changing suffix (64 bits)
    <<h5::16, h6::16, h7::16, h8::16>> = <<i::64>>

    ip = {h1, h2, h3, h4, h5, h6, h7, h8}
    port = 1024 + rem(i, 64512)
    PeerID.new(ip, port)
  end

  defp generate_fake_peer_data(_i) do
    %PeerData{
      country: "CN",
      last_updated: System.system_time(:millisecond)
    }
    |> PeerData.update_uploaded(Enum.random(0..(1024*1024*1024)))
    |> PeerData.update_downloaded(Enum.random(0..(1024*1024*1024)))
    |> PeerData.update_left(Enum.random(0..(1024*1024*1024)))
  end

  defp fill_table(table, n, peer_fn, compact) do
    for i <- 1..n do
      id = peer_fn.(i)
      data = generate_fake_peer_data(i)

      id = if compact do PeerID.to_storage(id) else id end
      peer = {id, data}
      :ets.insert(table, peer)
    end
  end

  defp ets_table_memory(table), do: :ets.info(table)[:memory]

  defp get_memory_delta(table, n, family, compact) do
    peer_fn = case family do
      :inet -> &generate_fake_peer_ipv4/1
      :inet6 -> &generate_fake_peer_ipv6/1
    end

    mem_before = ets_table_memory(table)
    fill_table(table, n, peer_fn, compact)
    mem_after = ets_table_memory(table)
    used = mem_after - mem_before
    used * :erlang.system_info(:wordsize)
  end

  describe "ETS peer memory usage" do
    setup do
      # create all tables for all tests to simplify
      table_v4nn = :ets.new(:table_v4nn, [:set, :public])
      table_v4sn = :ets.new(:table_v4sn, [:set, :public])
      table_v4nc = :ets.new(:table_v4nc, [:set, :public, :compressed])
      table_v4sc = :ets.new(:table_v4sc, [:set, :public, :compressed])

      table_v6nn = :ets.new(:table_v6nn, [:set, :public])
      table_v6sn = :ets.new(:table_v6sn, [:set, :public])
      table_v6nc = :ets.new(:table_v6nc, [:set, :public, :compressed])
      table_v6sc = :ets.new(:table_v6sc, [:set, :public, :compressed])

      tables = %{
        table_v4nn: table_v4nn,
        table_v4sn: table_v4sn,
        table_v4nc: table_v4nc,
        table_v4sc: table_v4sc,

        table_v6nn: table_v6nn,
        table_v6sn: table_v6sn,
        table_v6nc: table_v6nc,
        table_v6sc: table_v6sc
      }

      {:ok, tables: tables}
    end

    test "IPv4 PeerID vs compressed PeerID", %{tables: tables} do
      results =
        for n <- @sizes do
          normal = get_memory_delta(tables.table_v4nn, n, :inet, false)
          compressed = get_memory_delta(tables.table_v4nc, n, :inet, false)

          %{
            size: n,
            normal: normal,
            compressed: compressed
          }
        end

      for result <- results do
        %{size: n, normal: p, compressed: c} = result

        IO.puts("""
        * #{n} peers:
          PeerID     -> #{p} bytes
          PeerID (c) -> #{c} bytes
        """)

        assert c <= p, "compressed table should use less memory than normal"
      end
    end

    test "IPv4 Storage vs compressed Storage", %{tables: tables} do
      results =
        for n <- @sizes do
          storage = get_memory_delta(tables.table_v4sn, n, :inet, true)
          compressed = get_memory_delta(tables.table_v4sc, n, :inet, true)

          %{
            size: n,
            storage: storage,
            compressed: compressed
          }
        end

      for result <- results do
        %{size: n, storage: s, compressed: c} = result

        IO.puts("""
        * #{n} peers:
          Storage     -> #{s} bytes
          Storage (c) -> #{c} bytes
        """)

        assert c <= s, "compressed table should use less memory than normal"
      end
    end

    test "IPv4 PeerID vs Storage no compression", %{tables: tables} do
      results =
        for n <- @sizes do
          peerid = get_memory_delta(tables.table_v4nn, n, :inet, false)
          storage = get_memory_delta(tables.table_v4sn, n, :inet, true)

          %{
            size: n,
            peerid: peerid,
            storage: storage
          }
        end

      for result <- results do
        %{size: n, peerid: p, storage: s} = result

        IO.puts("""
        * #{n} peers:
          PeerID  -> #{p} bytes
          Storage -> #{s} bytes
        """)

        assert s <= p, "storage type should use less memory than normal id"
      end
    end

    test "IPv4 PeerID vs Storage compressed", %{tables: tables} do
      results =
        for n <- @sizes do
          peerid = get_memory_delta(tables.table_v4nc, n, :inet, false)
          storage = get_memory_delta(tables.table_v4sc, n, :inet, true)

          %{
            size: n,
            peerid: peerid,
            storage: storage
          }
        end

      for result <- results do
        %{size: n, peerid: p, storage: s} = result

        IO.puts("""
        * #{n} peers:
          PeerID (c)  -> #{p} bytes
          Storage (c) -> #{s} bytes
        """)

        assert s <= p, "storage type should use less memory than normal id"
      end
    end
  end

  describe "ETS table memory usage" do
    test "empty ETS table memory usage" do
      for n <- @sizes do
        ets_before = :erlang.memory(:ets)

        tables = for i <- 1..n do
          :ets.new(:"test_empty_#{n}_#{i}", [:set, :public, read_concurrency: true])
        end

        ets_after = :erlang.memory(:ets)
        total_delta = ets_after - ets_before

        total_table_bytes =
          tables
          |> Enum.map(&(:ets.info(&1, :memory)))
          |> Enum.sum()
          |> Kernel.*(:erlang.system_info(:wordsize))

        per_table_bytes = total_table_bytes / n

        Enum.each(tables, &:ets.delete/1)
        :erlang.garbage_collect()

        result = %{
          total_overhead_bytes: total_table_bytes,
          total_overhead_mb: total_table_bytes / (1024 ** 2),
          avg_overhead_per_table_bytes: per_table_bytes,
          avg_overhead_per_table_kb: per_table_bytes / 1024,
          total_delta_bytes: total_delta,
          total_delta_mb: total_delta / (1024 ** 2)
        }

        IO.inspect(result, label: "ETS #{n} tables memory")

        assert result.total_overhead_bytes > 0
        assert result.total_overhead_mb > 0
        assert result.avg_overhead_per_table_bytes > 0
        assert result.avg_overhead_per_table_kb > 0
      end
    end
  end
end
