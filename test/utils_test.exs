defmodule ExTrackerTest.UtilsTest do
  use ExUnit.Case, async: true

  alias ExTracker.Utils

  describe "pad_to_8_bytes/1" do
    test "add padding when the binary size is less than 8 bytes" do
      input = "cat"  # 3 bytes
      result = Utils.pad_to_8_bytes(input)
      assert byte_size(result) == 8
      assert result == <<0, 0, 0, 0, 0>> <> input
    end

    test "leave the binary as is if the size is 8 bytes" do
      input = "12345678" # 8 bytes
      result = Utils.pad_to_8_bytes(input)
      assert result == input
    end

    test "leave the binary as is if the size is bigger than 8 bytes" do
      input = "123456789"  # 9 bytes
      result = Utils.pad_to_8_bytes(input)
      assert result == input
    end
  end

  describe "hash_to_string/1" do
    test "convert a binary hash into a downcase hexadecimal string" do
      hash = <<0, 15, 255>>
      expected = String.downcase(Base.encode16(hash))
      result = Utils.hash_to_string(hash)
      assert result == expected
    end
  end

  describe "ip_to_bytes/1" do
    test "convert an IPv4 tuple into a binary" do
      ip = {127, 0, 0, 1}
      result = Utils.ip_to_bytes(ip)
      assert result == <<127, 0, 0, 1>>
    end

    test "convert an IPv6 tuple into a binary" do
      ip = {9225, 35413, 38466, 7920, 14778, 38138, 22855, 51913}
      result = Utils.ip_to_bytes(ip)
      assert result == <<36, 9, 138, 85, 150, 66, 30, 240, 57, 186, 148, 250, 89, 71, 202, 201>>
    end
  end

  describe "ipv4_to_bytes/1" do
    test "convert an IPv4 string to a binary" do
      ip_str = "192.168.1.1"
      result = Utils.ipv4_to_bytes(ip_str)
      assert result == <<192, 168, 1, 1>>
    end
  end

  describe "port_to_bytes/1" do
    test "convert network port number into a big-endian 16bit binary" do
      port = 8080
      result = Utils.port_to_bytes(port)
      expected = <<port::16>>
      assert result == expected
    end
  end

  describe "get_configured_ipv4/0" do
    setup do
      Application.put_env(:extracker, :ipv4_bind_address, "127.0.0.1")
      :ok
    end

    test "return the ip defined in :ipv4_bind_address as a tuple" do
      result = Utils.get_configured_ipv4()
      assert result == {127, 0, 0, 1}
    end
  end

  describe "get_configured_ipv6/0" do
    setup do
      Application.put_env(:extracker, :ipv6_bind_address, "::1")
      :ok
    end

    test "return the ip defined in :ipv6_bind_address as a tuple" do
      result = Utils.get_configured_ipv6()
      assert result == {0, 0, 0, 0, 0, 0, 0, 1}
    end
  end

  describe "validate_hash/1" do
    test "validate a 40 byte hexadecimal string" do
      valid_binary = :crypto.strong_rand_bytes(20)
      valid_hex = Base.encode16(valid_binary) |> String.downcase()
      assert byte_size(valid_hex) == 40
      assert Utils.validate_hash(valid_hex) == {:ok, valid_binary}
    end

    test "return an error when the hash is not valid hexadecimal" do
      invalid_hex = "zz" <> String.duplicate("0", 38)
      assert Utils.validate_hash(invalid_hex) == {:error, "invalid hex-string hash"}
    end

    test "validate a 32 byte base32 hash" do
      valid_binary = :crypto.strong_rand_bytes(20)
      valid_base32 = Base.encode32(valid_binary, case: :upper)
      assert byte_size(valid_base32) == 32
      assert Utils.validate_hash(valid_base32) == {:ok, valid_binary}
    end

    test "return an error for invalid base32 hash" do
      invalid_base32 = String.slice("INVALIDBASE32HASHVALUE12345678" <> "AAAAAA", 0, 32)
      assert Utils.validate_hash(invalid_base32) == {:error, "invalid base32 hash"}
    end

    test "validate a 20 byte binary hash" do
      valid_binary = :crypto.strong_rand_bytes(20)
      assert Utils.validate_hash(valid_binary) == {:ok, valid_binary}
    end

    test "validate a hash as a 20 item list" do
      valid_binary = :crypto.strong_rand_bytes(20)
      valid_list = :erlang.binary_to_list(valid_binary)
      assert Utils.validate_hash(valid_list) == {:ok, valid_binary}
    end

    test "return an error if the hash size is invalid" do
      assert Utils.validate_hash(:crypto.strong_rand_bytes(5)) == {:error, "invalid hash"}
      assert Utils.validate_hash(:crypto.strong_rand_bytes(50)) == {:error, "invalid hash"}
    end
  end
end
