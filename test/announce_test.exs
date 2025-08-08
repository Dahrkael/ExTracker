
defmodule ExTrackerTest.AnnounceTest do
  use ExUnit.Case, async: true

  alias ExTracker.Processors.Announce

  @source_ip {127, 0, 0, 1}

  @valid_params %{
    "info_hash"  => <<67, 235, 5, 218, 118, 194, 91, 240, 38, 247, 16, 121, 195, 64, 217, 74, 14, 46, 101, 204>>,
    "peer_id"    => "-GO0001-995b26d3b44e",
    "ip"         => nil,
    "port"       => 1337,
    "uploaded"   => 902_110_211,
    "downloaded" => 1_011_849_280,
    "left"       => 854_204_383,
    "compact"    => 0,
    "event"      => "",
    "numwant"    => -1,
    "options"    => %{urldata: "/announce"},
    "key"        => nil
  }

  describe "process/2 - early out on invalid announce" do
    test "missing info_hash returns an error" do
      params = Map.delete(@valid_params, "info_hash")

      assert {:error, _reason} = Announce.process(@source_ip, params)
    end

    test "missing peer_id returns an error" do
      params = Map.delete(@valid_params, "peer_id")

      assert {:error, _reason} = Announce.process(@source_ip, params)
    end

    test "missing port returns an error" do
      params = Map.delete(@valid_params, "port")

      assert {:error, _reason} = Announce.process(@source_ip, params)
    end

    test "missing uploaded returns an error" do
      params = Map.delete(@valid_params, "uploaded")

      assert {:error, _reason} = Announce.process(@source_ip, params)
    end

    test "missing downloaded returns an error" do
      params = Map.delete(@valid_params, "downloaded")

      assert {:error, _reason} = Announce.process(@source_ip, params)
    end

    test "missing left returns an error" do
      params = Map.delete(@valid_params, "left")

      assert {:error, _reason} = Announce.process(@source_ip, params)
    end
  end

  describe "process/2 returns peers correctly" do
    test "return leechers for seeders" do
      seeder_params = @valid_params
      |> Map.put("info_hash", <<67, 235, 5, 218, 118, 194, 91, 240, 38, 247, 16, 121, 195, 64, 217, 74, 14, 46, 101, 2>>)
        |> Map.put("left", 0)
        |> Map.put("port", 1338)
        |> Map.put("peer_id", "-GO0001-seeder000000")

      leecher_params = @valid_params
      |> Map.put("info_hash", <<67, 235, 5, 218, 118, 194, 91, 240, 38, 247, 16, 121, 195, 64, 217, 74, 14, 46, 101, 2>>)
        |> Map.put("left", 3495839456)
        |> Map.put("port", 1339)
        |> Map.put("peer_id", "-GO0001-leecher00000")

      assert {:ok, _response} = Announce.process(@source_ip, leecher_params)
      assert {:ok, response} = Announce.process(@source_ip, seeder_params)

      assert %{"incomplete" => 1, "peers" => <<127, 0, 0, 1, 5, 59, rest::binary>> } = response
    end

    test "return seeders for leechers" do
      seeder_params = @valid_params
        |> Map.put("info_hash", <<67, 235, 5, 218, 118, 194, 91, 240, 38, 247, 16, 121, 195, 64, 217, 74, 14, 46, 101, 1>>)
        |> Map.put("left", 0)
        |> Map.put("port", 1338)
        |> Map.put("peer_id", "-GO0001-seeder000000")

      leecher_params = @valid_params
        |> Map.put("info_hash", <<67, 235, 5, 218, 118, 194, 91, 240, 38, 247, 16, 121, 195, 64, 217, 74, 14, 46, 101, 1>>)
        |> Map.put("left", 3495839456)
        |> Map.put("port", 1339)
        |> Map.put("peer_id", "-GO0001-leecher00000")

      assert {:ok, _response} = Announce.process(@source_ip, seeder_params)
      assert {:ok, response} = Announce.process(@source_ip, leecher_params)

      assert %{"complete" => 1, "peers" => <<127, 0, 0, 1, 5, 58, rest::binary>> } = response
    end
  end
end
