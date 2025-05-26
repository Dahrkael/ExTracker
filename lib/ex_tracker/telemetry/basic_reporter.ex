defmodule ExTracker.Telemetry.BasicReporter do
    use GenServer
    require Logger

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
      "#{inspect(metrics)}"
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

      {new, updated} = Map.get_and_update(data, key, fn current ->
        new = if current == nil, do: 1, else: current + 1
        {current, new}
      end)

      Logger.debug("counter updated: #{inspect(metric)}/#{inspect(metadata)} - value: #{new}")
      {:noreply, Map.put(state, metric, updated)}
    end

    @impl true
    def handle_cast({:sum, metric, value, metadata}, state) do
      data = Map.get(state, metric)
      key = get_target_key(metadata)

      {new, updated} = Map.get_and_update(data, key, fn current ->
        new = if current == nil, do: value, else: current + value
        {current, new}
      end)

      Logger.debug("sum updated: #{inspect(metric)}/#{inspect(metadata)} - value: #{new}")
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
