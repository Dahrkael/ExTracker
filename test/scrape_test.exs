defmodule ExTrackerTest.ScrapeTest do
  use ExUnit.Case, async: false

  alias ExTracker.Processors.Announce
  alias ExTracker.Processors.Scrape

  @source_ip {127, 0, 0, 1}

  @base_params %{
    "info_hash"  => <<67, 235, 5, 218, 118, 194, 91, 240, 38, 247, 16, 121, 195, 64, 217, 74, 14, 46, 101, 210>>,
    "peer_id"    => "-GO0001-995b26d3b44e",
    "ip"         => nil,
    "port"       => 22337,
    "uploaded"   => 0,
    "downloaded" => 0,
    "left"       => 123,
    "compact"    => 1,
    "event"      => "",
    "numwant"    => -1,
    "options"    => %{urldata: "/announce"},
    "key"        => nil
  }

  describe "scrape downloaded uses snatch counter" do
    test "increments once when a peer completes" do
      announce_1 = @base_params
      |> Map.put("port", 22338)
      |> Map.put("peer_id", "-GO0001-scrapepeer0001")
      |> Map.put("left", 10)

      announce_completed = announce_1
      |> Map.put("left", 0)
      |> Map.put("event", "completed")

      assert {:ok, _} = Announce.process(@source_ip, announce_1)
      assert {:ok, _} = Announce.process(@source_ip, announce_completed)

      scrape_params = %{"info_hash" => @base_params["info_hash"]}
      assert {:ok, response} = Scrape.process(@source_ip, scrape_params)
      assert %{"downloaded" => 1} = response
    end

    test "does not increment more than once for duplicate completion announces" do
      announce_1 = @base_params
      |> Map.put("port", 22339)
      |> Map.put("peer_id", "-GO0001-scrapepeer0002")
      |> Map.put("left", 9)

      announce_completed = announce_1
      |> Map.put("left", 0)
      |> Map.put("event", "completed")

      assert {:ok, _} = Announce.process(@source_ip, announce_1)
      assert {:ok, _} = Announce.process(@source_ip, announce_completed)
      assert {:ok, _} = Announce.process(@source_ip, announce_completed)

      scrape_params = %{"info_hash" => @base_params["info_hash"]}
      assert {:ok, response} = Scrape.process(@source_ip, scrape_params)
      assert %{"downloaded" => 1} = response
    end
  end
end