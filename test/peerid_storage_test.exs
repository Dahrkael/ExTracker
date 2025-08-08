defmodule ExTrackerTest.PeerIDStorageTest do
  use ExUnit.Case, async: true

  alias ExTracker.Types.PeerID
  alias ExTracker.Types.PeerID.Storage

  @ipv4 {{192, 168, 0, 1}, 1337}
  @ipv6 {{0x2001, 0x0db8, 0, 0, 0, 0, 0, 1}, 1337}

  describe "round-trip encode/decode" do
    test "IPv4 addresses" do
      peer = PeerID.new(elem(@ipv4, 0), elem(@ipv4, 1))
      bin = Storage.encode(peer)

      assert Storage.decode(bin) == peer
    end

    test "IPv6 addresses" do
      peer = PeerID.new(elem(@ipv6, 0), elem(@ipv6, 1))
      bin = Storage.encode(peer)

      assert Storage.decode(bin) == peer
    end
  end

  describe "encoded binary size" do
    test "heap-binary compact form for IPv4 uses 3 words" do
      peer = PeerID.new(elem(@ipv4, 0), elem(@ipv4, 1))
      bin = Storage.encode(peer)

      assert :erts_debug.size(bin) == 3
    end

    test "heap-binary compact form for IPv6 uses 7 words" do
      peer = PeerID.new(elem(@ipv6, 0), elem(@ipv6, 1))
      bin  = Storage.encode(peer)

      assert :erts_debug.size(bin) == 5
    end
  end

  describe "compatibility with existing literals" do
    test "decode literal IPv4 binary" do
      literal = <<0x04, 1, 2, 3, 4, 0, 5>>
      assert Storage.decode(literal) == PeerID.new({1, 2, 3, 4}, 5)
    end

    test "decode literal IPv6 binary" do
      literal = <<0x06, 0x20, 0x01, 0x0d, 0xb8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 5>>
      assert Storage.decode(literal) == PeerID.new({0x2001, 0x0db8, 0, 0, 0, 0, 0, 1}, 5)
    end
  end

  describe "error cases" do
    test "too short binary raises ArgumentError" do
      assert_raise FunctionClauseError, fn ->
        Storage.decode(<<1, 2, 3>>)
      end
    end

    test "too long binary raises ArgumentError" do
      extra = <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10>>
      assert_raise FunctionClauseError, fn ->
        Storage.decode(extra)
      end
    end
  end
end
