defmodule PeerIDTest do
  use ExUnit.Case, async: true

  alias ExTracker.Types.PeerID
  alias ExTracker.Types.PeerID.Storage

  describe "PeerID creation" do
    test "creates a valid IPv4 PeerID" do
      ip = {192, 168, 1, 1}
      port = 1337
      peer = PeerID.new(ip, port)

      assert peer.family == :inet
      assert peer.ip == ip
      assert peer.port == port
    end

    test "creates a valid IPv6 PeerID" do
      ip = {0x2001, 0xdb8, 0, 0, 0, 0, 0, 1}
      port = 1337
      peer = PeerID.new(ip, port)

      assert peer.family == :inet6
      assert peer.ip == ip
      assert peer.port == port
    end

    test "raises on invalid IP tuple" do
      assert_raise ArgumentError, fn ->
        PeerID.new({1, 2, 3}, 1234)
      end

      assert_raise ArgumentError, fn ->
        PeerID.new({1, 2, 3, 4, 5}, 1234)
      end
    end

    test "raises on invalid port" do
      assert_raise ArgumentError, fn ->
        PeerID.new({192, 168, 1, 1}, -1)
      end

      assert_raise ArgumentError, fn ->
        PeerID.new({192, 168, 1, 1}, 70000)
      end
    end
  end

  describe "PeerID equality and comparison" do
    test "two identical PeerIDs are equal" do
      ip = {192, 168, 1, 1}
      port = 1337
      a = PeerID.new(ip, port)
      b = PeerID.new(ip, port)

      assert a == b
    end

    test "different IPs are not equal" do
      a = PeerID.new({192, 168, 1, 1}, 1234)
      b = PeerID.new({192, 168, 1 ,2}, 1234)

      refute a == b
    end

    test "different ports are not equal" do
      a = PeerID.new({192, 168, 1, 1}, 1234)
      b = PeerID.new({192, 168, 1, 1}, 4321)

      refute a == b
    end

    test "IPv4 and IPv6 with same octets are not equal" do
      ipv4 = PeerID.new({10,0,0,1}, 1234)
      ipv6 = PeerID.new({0,0,0,0,0,0,0,0x0a00_0001}, 1234)

      refute ipv4 == ipv6
    end
  end

  describe "PeerID.inspect/1" do
    test "formats IPv4 correctly" do
      peer = PeerID.new({192, 168, 1, 1}, 1337)
      assert "#{peer}" =~ "192.168.1.1:1337"
    end

    test "formats IPv6 correctly" do
      peer = PeerID.new({0x2001, 0xdb8, 0, 0, 0, 0, 0, 1}, 1337)
      assert "#{peer}" =~ "[2001:0db8:0000:0000:0000:0000:0000:0001]:1337"
    end
  end
end
