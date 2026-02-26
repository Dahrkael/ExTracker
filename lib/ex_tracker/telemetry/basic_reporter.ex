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

    def handle_event(_event_name, measurements, metadata, metric_ops) do
      GenServer.cast(__MODULE__, {:metrics_batch, metric_ops, measurements, metadata})
    end

    defp to_metric_op(%Telemetry.Metrics.Counter{} = metric) do
      {:counter, metric.name}
    end

    defp to_metric_op(%Telemetry.Metrics.Sum{} = metric) do
      {:sum, metric.name, metric.measurement}
    end

    defp to_metric_op(%Telemetry.Metrics.LastValue{} = metric) do
      {:last, metric.name, metric.measurement}
    end

    defp to_metric_op(metric) do
      Logger.error("Unsupported metric: #{metric.__struct__}. #{inspect(metric.event_name)}")
      nil
    end

    def render_metrics_html() do
      metrics = GenServer.call(__MODULE__, {:get_metrics})
      render_metrics_html(metrics)
    end

    def render_metrics_html(metrics) do
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

      http_announce_rate_ipv4 = get_in(metrics, [[:extracker, :request, :processing_time, :count], %{family: "inet", action: "announce", endpoint: "http"}, :rate]) || 0
      http_announce_rate_ipv6 = get_in(metrics, [[:extracker, :request, :processing_time, :count], %{family: "inet6", action: "announce", endpoint: "http"}, :rate]) || 0
      http_announce_rate_all = http_announce_rate_ipv4 + http_announce_rate_ipv6

      http_scrape_rate_ipv4 = get_in(metrics, [[:extracker, :request, :processing_time, :count], %{family: "inet", action: "scrape", endpoint: "http"}, :rate]) || 0
      http_scrape_rate_ipv6 = get_in(metrics, [[:extracker, :request, :processing_time, :count], %{family: "inet6", action: "scrape", endpoint: "http"}, :rate]) || 0
      http_scrape_rate_all = http_scrape_rate_ipv4 + http_scrape_rate_ipv6

      http_failure_rate_all =
        Map.get(metrics, [:extracker, :request, :failure, :count], %{})
        |> Enum.filter(fn {key, _value} -> key[:endpoint] == "http" end)
        |> Enum.map(fn {_key, value} -> value[:rate] end)
        |> Enum.sum()

      http_failure_rate_ipv4 =
        Map.get(metrics, [:extracker, :request, :failure, :count], %{})
        |> Enum.filter(fn {key, _value} -> key[:endpoint] == "http" and key[:family] == "inet" end)
        |> Enum.map(fn {_key, value} -> value[:rate] end)
        |> Enum.sum()

      http_failure_rate_ipv6 =
        Map.get(metrics, [:extracker, :request, :failure, :count], %{})
        |> Enum.filter(fn {key, _value} -> key[:endpoint] == "http" and key[:family] == "inet6" end)
        |> Enum.map(fn {_key, value} -> value[:rate] end)
        |> Enum.sum()

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
  <meta http-equiv=refresh content=60>
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
    <thead><tr><th colspan="4">HTTP Responses (per second)</th></tr></thead>
    <thead><tr><th>Action</th><th>Total</th><th>IPv4</th><th>IPv6</th></tr></thead>
    <tbody>
      <tr>
        <td>announce</td>
        <td>#{trunc(http_announce_rate_all)}</td>
        <td>#{trunc(http_announce_rate_ipv4)}</td>
        <td>#{trunc(http_announce_rate_ipv6)}</td>
      </tr>
      <tr>
        <td>scrape</td>
        <td>#{trunc(http_scrape_rate_all)}</td>
        <td>#{trunc(http_scrape_rate_ipv4)}</td>
        <td>#{trunc(http_scrape_rate_ipv6)}</td>
      </tr>

      <tr>
        <td>failure</td>
        <td>#{trunc(http_failure_rate_all)}</td>
        <td>#{trunc(http_failure_rate_ipv4)}</td>
        <td>#{trunc(http_failure_rate_ipv6)}</td>
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
      groups =
        metrics
        |> Enum.group_by(& &1.event_name)
        |> Enum.map(fn {event, event_metrics} ->
          ops =
            event_metrics
            |> Enum.map(&to_metric_op/1)
            |> Enum.reject(&is_nil/1)

          {event, ops}
        end)
        |> Map.new()

      for {event, metric_ops} <- groups do
        id = {__MODULE__, event, self()}
        :telemetry.attach(id, event, &__MODULE__.handle_event/4, metric_ops)
      end

      metrics_state =
        metrics
        |> Enum.reduce(%{}, fn metric, acc ->
          Map.put_new(acc, metric.name, %{})
        end)

      state = %{
        events: Map.keys(groups),
        metrics: metrics_state
      }

      {:ok, state}
    end

    @impl true
    def terminate(_, %{events: events}) do
      for event <- events do
        :telemetry.detach({__MODULE__, event, self()})
      end

      :ok
    end

    @impl true
    def handle_call({:get_metrics}, _from, state) do
      {:reply, state.metrics, state}
    end

    @impl true
    def handle_cast({:metrics_batch, metric_ops, measurements, metadata}, state) do
      key = get_target_key(metadata)
      now  = System.monotonic_time(:second)

      updated_metrics =
        Enum.reduce(metric_ops, state.metrics, fn metric_op, metrics_state ->
          apply_metric_op(metric_op, measurements, key, now, metrics_state)
        end)

      {:noreply, %{state | metrics: updated_metrics}}
    end

    defp apply_metric_op({:counter, metric}, _measurements, key, now, metrics_state) do
      update_rate_metric(metrics_state, metric, key, 1, now)
    end

    defp apply_metric_op({:sum, metric, measurement}, measurements, key, now, metrics_state) do
      case Map.get(measurements, measurement) do
        value when is_number(value) ->
          update_rate_metric(metrics_state, metric, key, value, now)

        _other ->
          metrics_state
      end
    end

    defp apply_metric_op({:last, metric, measurement}, measurements, key, _now, metrics_state) do
      case Map.fetch(measurements, measurement) do
        {:ok, value} ->
          metric_data = Map.get(metrics_state, metric, %{})
          updated = Map.put(metric_data, key, value)

          Map.put(metrics_state, metric, updated)

        :error ->
          metrics_state
      end
    end

    defp update_rate_metric(metrics_state, metric, key, increment, now) do
      metric_data = Map.get(metrics_state, metric, %{})
      new_entry = update_rate_entry(Map.get(metric_data, key), increment, now)
      updated = Map.put(metric_data, key, new_entry)

      Map.put(metrics_state, metric, updated)
    end

    defp update_rate_entry(nil, increment, now) do
      %{prev: 0, value: increment, ts: now, rate: 0}
    end

    defp update_rate_entry(%{prev: prev, value: current, ts: ts, rate: _rate} = entry, increment, now) do
      new_value = current + increment
      elapsed = now - ts

      if elapsed >= 1 do
        delta = new_value - prev
        rate = delta / elapsed
        %{entry | prev: new_value, value: new_value, ts: now, rate: rate}
      else
        %{entry | value: new_value}
      end
    end

    defp get_target_key(metadata) do
      case Kernel.map_size(metadata) do
        0 -> :default
        _n -> metadata
      end
    end
end
