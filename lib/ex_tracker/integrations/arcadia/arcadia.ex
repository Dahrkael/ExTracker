defmodule ExTracker.Integrations.Arcadia do

    use GenServer
    require Logger

    alias ExTracker.Utils
    alias ExTracker.Integrations.Arcadia.API

    def start_link(args) do
      GenServer.start_link(__MODULE__, args, name: __MODULE__)
    end

    #==========================================================================
    # Client
    #==========================================================================

    def add_torrent(info_hash, id, created_at) do
      GenServer.call(__MODULE__, {:add_torrent, {info_hash, id, created_at}})
    end

    def remove_torrent(info_hash) do
      GenServer.call(__MODULE__, {:remove_torrent, info_hash})
    end
    #==========================================================================
    # Server (callbacks)
    #==========================================================================

    @impl true
    def init(_args) do
      schedule_startup()
      {:ok, {}}
    end

    @impl true
    def terminate(_reason, _state) do
    end

    defp schedule_startup() do
      case Process.whereis(:whitelist_hashes) do
        nil ->
          Logger.warning("[integration][arcadia] Hashes Whitelist is not enabled")
        pid ->
          Process.monitor(pid)
          Process.send_after(self(), :registered_torrents, 1000)
      end
    end

    defp internal_add_torrent(info_hash, _id, _created_at) do
       case Utils.validate_hash(info_hash) do
        {:ok, hash} ->
          ExTracker.Accesslist.add(:whitelist_hashes, hash)
          :ok
        {:error, reason} ->
          Logger.warning("[integration][arcadia] can't add torrent with invalid info_hash '#{info_hash}'. reason: #{reason}")
          :error
        end
    end

    defp internal_remove_torrent(info_hash) do
      case Utils.validate_hash(info_hash) do
        {:ok, hash} ->
          ExTracker.Accesslist.remove(:whitelist_hashes, hash)
          :ok
        {:error, reason} ->
          Logger.warning("[integration][arcadia] can't remove torrent with invalid info_hash '#{info_hash}'. reason: #{reason}")
          :error
        end
    end

    @impl true
    def handle_call({:add_torrent, {info_hash, id, created_at}}, _from, state) do
      ret = internal_add_torrent(info_hash, id, created_at)
      {:reply, ret, state}
    end

    @impl true
    def handle_call({:remove_torrent, info_hash}, _from, state) do
      ret = internal_remove_torrent(info_hash)
      {:reply, ret, state}
    end

    @impl true
    def handle_info(:registered_torrents, state) do
      # if theres no whitelist then theres no point
      with true <- Utils.is_process_alive(:whitelist_hashes),
      # retrieve the torrent list from Arcadia's backend
        {:ok, torrents} <- API.get_registered_torrents()
      do
        # register each valid torrent in the hashes whitelist
        Logger.notice("[integration][arcadia] adding #{length(torrents)} registered torrents")
        {added, failed} = Task.async_stream(torrents, fn
            %{"created_at" => created_at, "id" => id, "info_hash" => info_hash} ->
              internal_add_torrent(info_hash, id, created_at)
            wrong_data ->
              Logger.warning("[integration][arcadia] invalid data format for registered torrent: #{inspect(wrong_data)}")
        end)
        |> Enum.reduce({0, 0}, fn
          {:ok, _result}, {a, f} -> {a + 1, f}
          _other, {a, f} -> {a, f + 1}
        end)
        Logger.notice("[integration][arcadia] added #{added} registered torrents (#{failed} failed)")
      else
        {:error, reason} ->
          Logger.error("[integration][arcadia] failed to get registered torrents: #{inspect(reason)}")
      end

      {:noreply, state}
    end

    @impl true
    def handle_info({:DOWN, _ref, :process, _object, _reason}, state) do
      # TODO hashes whitelist has gone down, regrab registered torrents once its back up
      {:noreply, state}
    end

    @impl true
    def handle_info(_msg, state) do
      {:noreply, state}
    end
  end
