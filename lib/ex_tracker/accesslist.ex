# ExTracker.Accesslist is a simple MapSet-like implementation using ETS so each
# process can do the lookups on its own
defmodule ExTracker.Accesslist do

  @table_prefix :accesslist

  use GenServer
  require Logger

  def start_link(args) do
    name = Keyword.get(args, :name, __MODULE__)
    GenServer.start_link(__MODULE__, args, name: name)
  end

  #==========================================================================
  # Client
  #==========================================================================

  def contains(name, entry) do
    table = :"#{@table_prefix}_#{name}"
    case :ets.lookup(table, entry) do
      [^entry] -> true
      _ -> false
    end
  end

  def add(name, entry), do: GenServer.cast(name, {:add, entry})
  def remove(name, entry), do: GenServer.cast(name, {:remove, entry})
  def from_file(name, path), do: GenServer.call(name, {:load_file, path})

  #==========================================================================
  # Server (callbacks)
  #==========================================================================

  @impl true
  def init(args) do
    name = Keyword.get(args, :name, __MODULE__)
    table = :"#{@table_prefix}_#{name}"
    ets_args = [:set, :named_table, :protected]
    :ets.new(table, ets_args)

    state = %{table: table}

    case Keyword.get(args, :file) do
      nil -> :ok
      path -> load_file(path, state)
    end

    {:ok, state}
  end

  @impl true
  def terminate(_reason, _state) do
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def handle_cast({:add, entry}, state) do
    case :ets.insert_new(state.table, {entry}) do
      true ->
        Logger.debug("accesslist #{state.table}: added entry '#{inspect(entry)}'")
      false ->
        Logger.debug("accesslist #{state.table}: entry '#{inspect(entry)}' already exists")
    end
    {:noreply, state}
  end

   @impl true
  def handle_cast({:remove, entry}, state) do
    with [^entry] <- :ets.lookup(state.table, entry),
      true <- :ets.delete(state.table, entry) do
        Logger.debug("accesslist #{state.table}: removed entry '#{inspect(entry)}'")
    else
      _ ->
        Logger.debug("accesslist #{state.table}: missing entry '#{inspect(entry)}'")
    end
    {:noreply, state}
  end

  @impl true
  def handle_call({:load_file, path}, _from, state) do
    load_file(path, state)
    {:reply, :ok, state}
  end

  defp load_file(path, state) do
    absolute_path = path |> Path.expand()
    # TODO could use File.Stream! with proper error handling if the list grows too big
    list = case File.read(absolute_path) do
      {:ok, data} ->
        list = data
        |> String.split("\n", trim: true)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
        |> MapSet.new()

        Logger.notice("loaded accesslist from file #{absolute_path} containing #{MapSet.size(list)} hashes")
        list
      {:error, error} ->
        Logger.error("failed to load access list from file '#{absolute_path}': #{:file.format_error(error)}")
        MapSet.new()
    end

    # clean the table first and then insert the data
    # TODO error handling, data races?
    :ets.delete_all_objects(state.table)
    list |> Enum.each(&(:ets.insert_new(state.table, {&1})))
  end
end
