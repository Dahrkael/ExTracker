defmodule ExTracker.Telemetry.EtsReporter do
  use GenServer
  require Logger

  @table :extracker_telemetry_ets_reporter

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def table_name(), do: @table

  def get_metrics() do
    GenServer.call(__MODULE__, :get_metrics)
  end

  def render_metrics_html() do
    metrics = get_metrics()
    ExTracker.Telemetry.BasicReporter.render_metrics_html(metrics)
  end

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

  @impl true
  def init(args) do
    Process.flag(:trap_exit, true)

    _ =
      :ets.new(@table, [
        :named_table,
        :set,
        :public,
        {:read_concurrency, true},
        {:write_concurrency, true}
      ])

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

    {:ok, %{events: Map.keys(groups)}}
  end

  @impl true
  def terminate(_, %{events: events}) do
    for event <- events do
      :telemetry.detach({__MODULE__, event, self()})
    end

    :ok
  end

  @impl true
  def handle_call(:get_metrics, _from, state) do
    metrics =
      @table
      |> :ets.tab2list()
      |> Enum.reduce(%{}, fn {{metric, key}, value}, acc ->
        metric_data = Map.get(acc, metric, %{})
        Map.put(acc, metric, Map.put(metric_data, key, value))
      end)

    {:reply, metrics, state}
  end

  @impl true
  def handle_cast({:metrics_batch, metric_ops, measurements, metadata}, state) do
    key = get_target_key(metadata)
    now = System.monotonic_time(:second)

    Enum.each(metric_ops, fn metric_op ->
      apply_metric_op(metric_op, measurements, key, now)
    end)

    {:noreply, state}
  end

  defp apply_metric_op({:counter, metric}, _measurements, key, now) do
    update_rate_metric(metric, key, 1, now)
  end

  defp apply_metric_op({:sum, metric, measurement}, measurements, key, now) do
    case Map.get(measurements, measurement) do
      value when is_number(value) -> update_rate_metric(metric, key, value, now)
      _other -> :ok
    end
  end

  defp apply_metric_op({:last, metric, measurement}, measurements, key, _now) do
    case Map.fetch(measurements, measurement) do
      {:ok, value} ->
        :ets.insert(@table, {{metric, key}, value})

      :error ->
        :ok
    end
  end

  defp update_rate_metric(metric, key, increment, now) do
    table_key = {metric, key}

    new_entry =
      case :ets.lookup(@table, table_key) do
        [] ->
          %{prev: 0, value: increment, ts: now, rate: 0}

        [{^table_key, entry}] when is_map(entry) ->
          update_rate_entry(entry, increment, now)

        [{^table_key, _other}] ->
          %{prev: 0, value: increment, ts: now, rate: 0}
      end

    :ets.insert(@table, {table_key, new_entry})
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
