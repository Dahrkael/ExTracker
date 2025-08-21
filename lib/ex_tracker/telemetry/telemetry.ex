defmodule ExTracker.Telemetry do
  use Supervisor
  require Logger
  import Telemetry.Metrics

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_arg) do
    children = [
      {:telemetry_poller,
        measurements: poller_measurements(),
        period: 60_000,
        init_delay: 10_000
      }
    ]
      ++ get_http_children()
      ++ get_basic_children()
      ++ get_prometheus_children()

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp get_http_children() do
    v4 = case Application.get_env(:extracker, :ipv4_enabled) do
      true ->
        [Supervisor.child_spec({Plug.Cowboy,
          scheme: :http,
          plug: ExTracker.Telemetry.Router,
          options: [
            net: :inet,
            ip: ExTracker.Utils.get_configured_ipv4(),
            port: Application.get_env(:extracker, :telemetry_port),
            compress: true,
            ref: "telemetry_router_inet",
            transport_options: [
              num_acceptors: System.schedulers_online(),
              max_connections: 1000,
            ]
          ]},
          id: :telemetry_supervisor_inet
        )]
      false -> []
    end

    v6 = case Application.get_env(:extracker, :ipv6_enabled) do
      true ->
        [Supervisor.child_spec({Plug.Cowboy,
          scheme: :http,
          plug: ExTracker.Telemetry.Router,
          options: [
            net: :inet6,
            ip: ExTracker.Utils.get_configured_ipv6(),
            port: Application.get_env(:extracker, :telemetry_port),
            compress: true,
            ref: "telemetry_router_inet6",
            ipv6_v6only: true,
            transport_options: [
              num_acceptors: System.schedulers_online(),
              max_connections: 1000,
            ]
          ]},
          id: :telemetry_supervisor_inet6
        )]
      false -> []
    end

    v4 ++ v6
  end

  defp get_basic_children() do
    case Application.get_env(:extracker, :telemetry_basic) do
      true ->
        Logger.notice("Telemetry Basic endpoint enabled")
        [{ExTracker.Telemetry.BasicReporter, metrics: metrics()}]
      _ -> []
    end
  end

  defp get_prometheus_children() do
     case Application.get_env(:extracker, :telemetry_prometheus) do
      true ->
        Logger.notice("Telemetry Prometheus endpoint enabled")
        [{TelemetryMetricsPrometheus.Core, metrics: metrics()}]
      _ -> []
    end
  end

  defp metrics do
    [
      # :telemetry.execute([:extracker, :request], %{processing_time: 0}, %{endpoint: "udp", action: "announce", family: "inet"})
      counter("extracker.request.processing_time.count", event_name: [:extracker, :request], measurement: :processing_time, tags: [:endpoint, :action, :family], unit: :microsecond),
      sum("extracker.request.processing_time.sum", event_name: [:extracker, :request], measurement: :processing_time, tags: [:endpoint, :action, :family], unit: :microsecond),
      # :telemetry.execute([:extracker, :request, :success], %{}, %{endpoint: "udp", action: "announce", family: "inet"})
      counter("extracker.request.success.count", tags: [:endpoint, :action, :family]),
      # :telemetry.execute([:extracker, :request, :failure], %{}, %{endpoint: "udp", action: "announce", family: "inet"})
      counter("extracker.request.failure.count", tags: [:endpoint, :action, :family]),
      # :telemetry.execute([:extracker, :request, :error], %{}, %{endpoint: "udp", action: "announce", family: "inet"})
      counter("extracker.request.error.count", tags: [:endpoint, :action, :family]),

      # :telemetry.execute([:extracker, :peer, :added], %{}, %{ family: "inet"})
      counter("extracker.peer.added.count", tags: [:family]),
      # :telemetry.execute([:extracker, :peer, :removed], %{}, %{ family: "inet"})
      counter("extracker.peer.removed.count", tags: [:family]),

      # :telemetry.execute([:extracker, :swarm, :created], %{})
      counter("extracker.swarm.created.count"),
      # :telemetry.execute([:extracker, :swarm, :destroyed], %{})
      counter("extracker.swarm.destroyed.count"),

      # :telemetry.execute([:extracker, :peers, :total], %{value: 0}, %{family: "inet"})
      last_value("extracker.peers.total.value", tags: [:family]),
      # :telemetry.execute([:extracker, :peers, :seeders], %{value: 0}, %{family: "inet"})
      last_value("extracker.peers.seeders.value", tags: [:family]),
      # :telemetry.execute([:extracker, :peers, :leechers], %{value: 0}, %{family: "inet"})
      last_value("extracker.peers.leechers.value", tags: [:family]),

      #:telemetry.execute([:extracker, :swarms, :total], %{value: 0})
      last_value("extracker.swarms.total.value"),

      # :telemetry.execute([:extracker, :bandwidth, :in], %{value: 0})
      sum("extracker.bandwidth.in.value"),
      # :telemetry.execute([:extracker, :bandwidth, :out], %{value: 0})
      sum("extracker.bandwidth.out.value"),

      #last_value("extracker.system.memory")
    ]
  end

  defp poller_measurements() do
    [
      #{:process_info, event: [:extracker, :system], name: ExTracker.Telemetry.Poller, keys: [:memory]},

      {ExTracker.Telemetry, :measure_swarms_totals, []},
      {ExTracker.Telemetry, :measure_peer_totals, []},
      {ExTracker.Telemetry, :reset_bandwidth, []},
    ]
  end

  def measure_peer_totals() do
    try do
      families = %{all: 0, inet: 0, inet6: 0}
      seeders = measure_peer_type(families, &ExTracker.Swarm.get_seeder_count/2)
      leechers = measure_peer_type(families, &ExTracker.Swarm.get_leecher_count/2)

      :telemetry.execute([:extracker, :peers, :seeders], %{value: seeders.all}, %{family: Atom.to_string(:all)})
      :telemetry.execute([:extracker, :peers, :seeders], %{value: seeders.inet}, %{family: Atom.to_string(:inet)})
      :telemetry.execute([:extracker, :peers, :seeders], %{value: seeders.inet6}, %{family: Atom.to_string(:inet6)})

      :telemetry.execute([:extracker, :peers, :leechers], %{value: leechers.all}, %{family: Atom.to_string(:all)})
      :telemetry.execute([:extracker, :peers, :leechers], %{value: leechers.inet}, %{family: Atom.to_string(:inet)})
      :telemetry.execute([:extracker, :peers, :leechers], %{value: leechers.inet6}, %{family: Atom.to_string(:inet6)})

      :telemetry.execute([:extracker, :peers, :total], %{value: (seeders.all + leechers.all)}, %{family: Atom.to_string(:all)})
      :telemetry.execute([:extracker, :peers, :total], %{value: (seeders.inet + leechers.inet)}, %{family: Atom.to_string(:inet)})
      :telemetry.execute([:extracker, :peers, :total], %{value: (seeders.inet6 + leechers.inet6)}, %{family: Atom.to_string(:inet6)})
    rescue
      e -> Logger.error("telemetry measure_peer_totals/1 failed to fully execute: #{Exception.message(e)}")
    catch
      type, value ->
        Logger.error("telemetry measure_peer_totals/1 failed to fully execute: #{inspect({type, value})}")
    end
  end

  def measure_peer_type(families, count_func) do
    families
    |> Enum.map( fn {family, _zero} ->
      total = ExTracker.SwarmFinder.get_swarm_list_stream()
      |> Task.async_stream(fn swarm -> count_func.(swarm, family) end, ordered: false)
      |> Stream.reject(&match?({_, :undefined}, &1))
      |> Stream.map(&elem(&1, 1))
      |> Stream.reject(&is_nil(&1))
      |> Enum.sum()

      {family, total}
    end)
    |> Map.new()
  end

  def measure_swarms_totals() do
    total = ExTracker.SwarmFinder.get_swarm_count()
    :telemetry.execute([:extracker, :swarms, :total], %{value: total})
  end

  def reset_bandwidth() do
    :telemetry.execute([:extracker, :bandwidth, :in], %{value: 0})
    :telemetry.execute([:extracker, :bandwidth, :out], %{value: 0})
  end
end
