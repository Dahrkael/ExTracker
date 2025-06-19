defmodule ExTracker.Telemetry.BasicReporter do
    use GenServer
    require Logger
    alias ExTracker.Utils

    def start_link(args) do
      GenServer.start_link(__MODULE__, args, name: __MODULE__)
    end

    #==========================================================================
    # Client
    #==========================================================================

    def handle_event(_event_name, measurements, metadata, metrics) do
      metrics |> Enum.map(&handle_metric(&1, measurements, metadata))
    end

    defp handle_metric(%Telemetry.Metrics.Counter{} = metric, _measurements, metadata) do
      GenServer.cast(__MODULE__, {:counter, metric.name, metadata})
    end

    defp handle_metric(%Telemetry.Metrics.Sum{} = metric, values, metadata) do
      values |> Enum.each(fn {_key, value} ->
        GenServer.cast(__MODULE__, {:sum, metric.name, value, metadata})
      end)
    end

    defp handle_metric(%Telemetry.Metrics.LastValue{} = metric, values, metadata) do
      values |> Enum.each(fn {_key, value} ->
        GenServer.cast(__MODULE__, {:last, metric.name, value, metadata})
      end)
    end

    defp handle_metric(metric, _measurements, _metadata) do
      Logger.error("Unsupported metric: #{metric.__struct__}. #{inspect(metric.event_name)}")
    end

    def render_metrics_html() do
      metrics = GenServer.call(__MODULE__, {:get_metrics})

      total_swarms = get_in(metrics, [[:extracker, :swarms, :total, :value], :default]) || 0
      bandwidth_in = get_in(metrics, [[:extracker, :bandwidth, :in, :value], :default, :rate]) || 0
      bandwidth_out = get_in(metrics, [[:extracker, :bandwidth, :out, :value], :default, :rate]) || 0

      peers_total_all = get_in(metrics, [[:extracker, :peers, :total, :value], %{family: "all"}]) || 0
      peers_total_ipv4 = get_in(metrics, [[:extracker, :peers, :total, :value], %{family: "inet"}]) || 0
      peers_total_ipv6 = get_in(metrics, [[:extracker, :peers, :total, :value], %{family: "inet6"}]) || 0
      peers_seeders_all = get_in(metrics, [[:extracker, :peers, :seeders, :value], %{family: "all"}]) || 0
      peers_seeders_ipv4 = get_in(metrics, [[:extracker, :peers, :seeders, :value], %{family: "inet"}]) || 0
      peers_seeders_ipv6 = get_in(metrics, [[:extracker, :peers, :seeders, :value], %{family: "inet6"}]) || 0
      peers_leechers_all = get_in(metrics, [[:extracker, :peers, :leechers, :value], %{family: "all"}]) || 0
      peers_leechers_ipv4 = get_in(metrics, [[:extracker, :peers, :leechers, :value], %{family: "inet"}]) || 0
      peers_leechers_ipv6 = get_in(metrics, [[:extracker, :peers, :leechers, :value], %{family: "inet6"}]) || 0

      udp_connect_rate_ipv4 = get_in(metrics, [[:extracker, :request, :processing_time, :count], %{family: "inet", action: "connect", endpoint: "udp"}, :rate]) || 0
      udp_connect_rate_ipv6 = get_in(metrics, [[:extracker, :request, :processing_time, :count], %{family: "inet6", action: "connect", endpoint: "udp"}, :rate]) || 0
      udp_connect_rate_all = udp_connect_rate_ipv4 + udp_connect_rate_ipv6

      udp_announce_rate_ipv4 = get_in(metrics, [[:extracker, :request, :processing_time, :count], %{family: "inet", action: "announce", endpoint: "udp"}, :rate]) || 0
      udp_announce_rate_ipv6 = get_in(metrics, [[:extracker, :request, :processing_time, :count], %{family: "inet6", action: "announce", endpoint: "udp"}, :rate]) || 0
      udp_announce_rate_all = udp_announce_rate_ipv4 + udp_announce_rate_ipv6

      udp_scrape_rate_ipv4 = get_in(metrics, [[:extracker, :request, :processing_time, :count], %{family: "inet", action: "scrape", endpoint: "udp"}, :rate]) || 0
      udp_scrape_rate_ipv6 = get_in(metrics, [[:extracker, :request, :processing_time, :count], %{family: "inet6", action: "scrape", endpoint: "udp"}, :rate]) || 0
      udp_scrape_rate_all = udp_scrape_rate_ipv4 + udp_scrape_rate_ipv6

      udp_failure_rate_all =
        Map.get(metrics, [:extracker, :request, :failure, :count], %{})
        |> Enum.filter(fn {key, _value} -> key[:endpoint] == "udp" end)
        |> Enum.map(fn {_key, value} -> value[:rate] end)
        |> Enum.sum()

      udp_failure_rate_ipv4 =
        Map.get(metrics, [:extracker, :request, :failure, :count], %{})
        |> Enum.filter(fn {key, _value} -> key[:endpoint] == "udp" and key[:family] == "inet" end)
        |> Enum.map(fn {_key, value} -> value[:rate] end)
        |> Enum.sum()

      udp_failure_rate_ipv6 =
        Map.get(metrics, [:extracker, :request, :failure, :count], %{})
        |> Enum.filter(fn {key, _value} -> key[:endpoint] == "udp" and key[:family] == "inet6" end)
        |> Enum.map(fn {_key, value} -> value[:rate] end)
        |> Enum.sum()

      html = """
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>ExTracker Statistics</title>
  <style>
    .cyan { color: cyan; text-shadow: 1px 1px 2px black; }
    .fuchsia { color: fuchsia; text-shadow: 1px 1px 2px black; }
    table { border-collapse: collapse; margin-bottom: 20px; }
    th, td { border: 1px solid #ccc; padding: 8px; text-align: left; }
    th { background-color: #f2f2f2; }
  </style>
</head>
<body>
  <h1><span class="fuchsia">Ex</span><span class="cyan">Tracker</span> Statistics</h1>

  <table>
    <thead><tr><th colspan="2">Swarms (Torrents)</th></tr></thead>
    <tbody>
      <tr><td>Current total</td><td>#{total_swarms}</td></tr>
    </tbody>
  </table>

  <table>
    <thead><tr><th colspan="4">Peers</th></tr></thead>
    <thead><tr><th>Type</th><th>Total</th><th>IPv4</th><th>IPv6</th></tr></thead>
    <tbody>
    <tr>
        <td>All</td>
        <td>#{peers_total_all}</td>
        <td>#{peers_total_ipv4}</td>
        <td>#{peers_total_ipv6}</td>
      </tr>
      <tr>
        <td>Seeders</td>
        <td>#{peers_seeders_all}</td>
        <td>#{peers_seeders_ipv4}</td>
        <td>#{peers_seeders_ipv6}</td>
      </tr>
      <tr>
        <td>Leechers</td>
        <td>#{peers_leechers_all}</td>
        <td>#{peers_leechers_ipv4}</td>
        <td>#{peers_leechers_ipv6}</td>
      </tr>
    </tbody>
  </table>

  <table>
    <thead><tr><th colspan="4">UDP Responses (per second)</th></tr></thead>
    <thead><tr><th>Action</th><th>Total</th><th>IPv4</th><th>IPv6</th></tr></thead>
    <tbody>
      <tr>
        <td>connect</td>
        <td>#{trunc(udp_connect_rate_all)}</td>
        <td>#{trunc(udp_connect_rate_ipv4)}</td>
        <td>#{trunc(udp_connect_rate_ipv6)}</td>
      </tr>
      <tr>
        <td>announce</td>
        <td>#{trunc(udp_announce_rate_all)}</td>
        <td>#{trunc(udp_announce_rate_ipv4)}</td>
        <td>#{trunc(udp_announce_rate_ipv6)}</td>
      </tr>
      <tr>
        <td>scrape</td>
        <td>#{trunc(udp_scrape_rate_all)}</td>
        <td>#{trunc(udp_scrape_rate_ipv4)}</td>
        <td>#{trunc(udp_scrape_rate_ipv6)}</td>
      </tr>

      <tr>
        <td>failure</td>
        <td>#{trunc(udp_failure_rate_all)}</td>
        <td>#{trunc(udp_failure_rate_ipv4)}</td>
        <td>#{trunc(udp_failure_rate_ipv6)}</td>
      </tr>
    </tbody>
  </table>

  <table>
    <thead>
      <tr>
        <th colspan="2">Bandwidth (per second)</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <td>RX (In)</td>
        <td>#{Utils.format_bits_as_string(bandwidth_in)}</td>
      </tr>
      <tr>
        <td>TX (Out)</td>
        <td>#{Utils.format_bits_as_string(bandwidth_out)}</td>
      </tr>
    </tbody>
  </table>
</body>
</html>
"""

      html
      #"#{inspect(metrics)}"
    end

    #==========================================================================
    # Server (callbacks)
    #==========================================================================

    @impl true
    def init(args) do
      Process.flag(:trap_exit, true)
      metrics = Keyword.get(args, :metrics, [])
      groups = Enum.group_by(metrics, & &1.event_name)

      for {event, metrics} <- groups do
        id = {__MODULE__, event, self()}
        :telemetry.attach(id, event, &__MODULE__.handle_event/4, metrics)
      end

      state = Enum.map(groups, fn {_event, metrics} ->
        Enum.map(metrics, fn metric -> {metric.name, %{}} end)
      end)
      |> List.flatten()
      |> Map.new()

      {:ok, state}
    end

    @impl true
    def terminate(_, events) do
      for event <- events do
        :telemetry.detach({__MODULE__, event, self()})
      end

      :ok
    end

    @impl true
    def handle_call({:get_metrics}, _from, state) do
      {:reply, state, state}
    end

    @impl true
    def handle_cast({:counter, metric, metadata}, state) do
      data = Map.get(state, metric)
      key = get_target_key(metadata)
      now  = System.monotonic_time(:second)

      new_entry = case Map.get(data, key) do
        nil ->
          %{prev: 0, value: 1, ts: now, rate: 0}
        %{prev: prev, value: current, ts: ts, rate: _rate} = entry ->
          new_value = current + 1
          elapsed = now - ts
          if elapsed >= 1 do
            delta = new_value - prev
            rate = delta / elapsed
            %{prev: current, value: new_value, ts: now, rate: rate}
          else
            Map.put(entry, :value, new_value)
          end
      end

    updated = Map.put(data, key, new_entry)

      Logger.debug("counter updated: #{inspect(metric)}/#{inspect(metadata)} - value: #{new_entry[:value]}")
      {:noreply, Map.put(state, metric, updated)}
    end

    @impl true
    def handle_cast({:sum, metric, value, metadata}, state) do
      data = Map.get(state, metric)
      key = get_target_key(metadata)
      now  = System.monotonic_time(:second)

      new_entry = case Map.get(data, key) do
        nil ->
          %{prev: 0, value: value, ts: now, rate: 0}
        %{prev: prev, value: current, ts: ts, rate: _rate} = entry ->
          new_value = current + value
          elapsed = now - ts
          if elapsed >= 1 do
            delta = new_value - prev
            rate = delta / elapsed
            %{prev: current, value: new_value, ts: now, rate: rate}
          else
            Map.put(entry, :value, new_value)
          end
      end

      updated = Map.put(data, key, new_entry)

      Logger.debug("sum updated: #{inspect(metric)}/#{inspect(metadata)} - value: #{new_entry[:value]}")
      {:noreply, Map.put(state, metric, updated)}
    end

    @impl true
    def handle_cast({:last, metric, value, metadata}, state) do
      data = Map.get(state, metric)
      key = get_target_key(metadata)

      updated = Map.put(data, key, value)

      Logger.debug("lastValue updated: #{inspect(metric)} - value: #{value}")
      {:noreply, Map.put(state, metric, updated)}
    end

    defp get_target_key(metadata) do
      case Kernel.map_size(metadata) do
        0 -> :default
        _n -> metadata
      end
    end
end
