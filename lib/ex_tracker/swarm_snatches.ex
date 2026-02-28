defmodule ExTracker.SwarmSnatches do
  use GenServer

  @table_name :swarm_snatches
  def table_name, do: @table_name

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(_args) do
    :ets.new(@table_name, [:set, :named_table, :public, write_concurrency: :auto])
    {:ok, %{}}
  end

  @impl true
  def terminate(_reason, _state) do
  end

  def create(hash) when is_binary(hash) do
    :ets.insert_new(@table_name, {hash, 0})
    :ok
  end

  def get(hash) when is_binary(hash) do
    case :ets.lookup(@table_name, hash) do
      [{^hash, count}] -> count
      _ -> 0
    end
  end

  def increment(hash) when is_binary(hash) do
    :ets.update_counter(@table_name, hash, {2, 1}, {hash, 0})
  end

  def put(hash, count) when is_binary(hash) and is_integer(count) and count >= 0 do
    :ets.insert(@table_name, {hash, count})
    :ok
  end

  def get_all() do
    :ets.tab2list(@table_name)
  end

  def maybe_delete(hash) when is_binary(hash) do
    case Application.get_env(:extracker, :snatches_delete_on_swarm_remove, false) do
      true ->
        :ets.delete(@table_name, hash)
        :ok
      _ -> :ok
    end
  end
end
