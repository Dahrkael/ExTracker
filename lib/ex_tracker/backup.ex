defmodule ExTracker.Backup do

  use GenServer
  require Logger

  alias ExTracker.Swarm
  alias ExTracker.SwarmFinder
  alias ExTracker.Types.SwarmID

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  #==========================================================================
  # Client
  #==========================================================================

  def make(path) do
    GenServer.cast(__MODULE__, {:make, path})
  end

  def make_sync(path) do
    GenServer.call(__MODULE__, {:make, path}, :infinity)
  end

  def restore(path) do
    GenServer.cast(__MODULE__, {:restore, path})
  end

  #==========================================================================
  # Server (callbacks)
  #==========================================================================

  @impl true
  def init(_args) do
    if Application.get_env(:extracker, :backup_auto_load_on_startup) do
      Application.get_env(:extracker, :backup_auto_path) |> restore()
    end

    schedule_backup()
    {:ok, {}}
  end

  @impl true
  def terminate(_reason, _state) do
  end

  defp schedule_backup() do
    Process.send_after(self(), :auto, Application.get_env(:extracker, :backup_auto_interval))
  end

  @impl true
  def handle_info(:auto, state) do
    if Application.get_env(:extracker, :backup_auto_enabled) do
      Logger.notice("auto backup triggered")
      Application.get_env(:extracker, :backup_auto_path) |> save()
    end

    # schedule the backup even if its disabled right now as it may be activated on runtime
    schedule_backup()
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def handle_call({:make, path}, _from, state) do
    save(path)
    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:make, path}, state) do
    save(path)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:restore, path}, state) do
    load(path)
    {:noreply, state}
  end

  defp save(file_path) do
    file_path = Path.expand(file_path)
    case create_path(file_path) do
      :ok ->
        Logger.notice("creating backup in #{file_path}")
        # retrieve all the existing swarms from the index
        swarm_entries = :ets.tab2list(SwarmFinder.swarms_table_name())
        # merge the actual swarm data (all the peers) with the index data
        swarms_backup = swarm_entries
          |> Task.async_stream(fn {hash, table, type, created_at, _last_cleaned} ->
            peers = try do
              swarm = SwarmID.new(hash, table, type)
              Swarm.get_all_peers(swarm, true)
            rescue
              e in ArgumentError ->
                Logger.debug("Backup.save/1: #{Exception.message(e)}")
                []
            end

            {hash, peers, created_at}
          end,
            max_concurrency: System.schedulers_online(),
            ordered: false)
          |> Enum.map(&elem(&1, 1))

        snatches_backup = ExTracker.SwarmSnatches.get_all()

        backup = %{
          swarms: swarms_backup,
          snatches: snatches_backup
        }

        File.write(file_path, :erlang.term_to_binary(backup))

        if Application.get_env(:extracker, :backup_display_stats) do
          ExTracker.Cmd.show_peer_count(:all)
          ExTracker.Cmd.show_swarm_count()
        end

        Logger.notice("backup created")
      :error ->
        Logger.error("backup failed")
    end
  end

  defp load(file_path) do
    file_path = Path.expand(file_path)
    Logger.notice("restoring backup from #{file_path}")
    if Application.get_env(:extracker, :backup_display_stats) do
      ExTracker.Cmd.show_peer_count(:all)
      ExTracker.Cmd.show_swarm_count()
    end

    backup =
      case File.read(file_path) do
        {:ok, binary} ->
          :erlang.binary_to_term(binary)
        {:error, reason} ->
          Logger.error("backup loading failed: #{reason}")
          %{}
      end

    case Map.fetch(backup, :swarms) do
      {:ok, swarms} ->
        swarms
        |> Task.async_stream(fn {hash, peers, created_at} ->
          # recreate the swarm
          {:ok, swarm} = SwarmFinder.find_or_create(hash) # FIXME this may fail if control list changes
          # put the correct creation date
          SwarmFinder.restore_creation_timestamp(hash, created_at)
          # TODO upgrade the swarm ->here<- if it has enough peers
          # insert all the missing peers
          Enum.each(peers, fn peer -> Swarm.insert_peer(swarm, peer, false) end)
        end,
          max_concurrency: System.schedulers_online(),
          ordered: false)
        |> Stream.run()

        Logger.notice("backup restored")

        case Map.fetch(backup, :snatches) do
          {:ok, snatches} when is_list(snatches) ->
            Enum.each(snatches, fn
              {hash, count} when is_binary(hash) and is_integer(count) and count >= 0 ->
                ExTracker.SwarmSnatches.put(hash, count)
              _other ->
                :ok
            end)
          _ ->
            :ok
        end

        if Application.get_env(:extracker, :backup_display_stats) do
          ExTracker.Cmd.show_peer_count(:all)
          ExTracker.Cmd.show_swarm_count()
        end
      :error -> :ok
    end
    :ok
  end

  # default path is gonna be the user's home directory
  defp create_path(path) do
    folder = case Path.split(path) do
      [_filename] -> Path.expand("~")
      parts -> Path.join(Enum.drop(parts, -1))
    end

    case File.mkdir_p(folder) do
      :ok -> :ok
      {:error, reason} ->
        Logger.error("error creating backup folder '#{folder}': #{inspect(reason)}")
        :error
    end
  end
end
