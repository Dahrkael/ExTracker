defmodule ExTracker.Backup do

  require Logger
  alias ExTracker.SwarmFinder

  # TODO measure how memory intense these operations actually are

  def save(file_path) do
    Logger.notice("creating backup into #{file_path}")
    # retrieve all the existing swarms from the index
    swarm_entries = :ets.tab2list(SwarmFinder.swarms_table_name())
    # merge the actual swarm data (all the peers) with the index data
    swarms_backup =
      Enum.map(swarm_entries, fn {hash, table, created_at, _last_cleaned} ->
        swarm_data = :ets.tab2list(table)
        {hash, swarm_data, created_at}
      end)

      backup = %{
      swarms: swarms_backup
    }

    File.write(file_path, :erlang.term_to_binary(backup))

    ExTracker.Cmd.show_peer_count()
    ExTracker.Cmd.show_swarm_count()
    Logger.notice("backup created")
  end

  def load(file_path) do
    Logger.notice("restoring backup from #{file_path}")
    ExTracker.Cmd.show_peer_count()
    ExTracker.Cmd.show_swarm_count()

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
        Enum.each(swarms, fn {hash, swarm_data, created_at} ->
          # recreate the swarm table
          swarm = SwarmFinder.find_or_create(hash)
          # put the correct creation date
          SwarmFinder.restore_creation_timestamp(hash, created_at)
          # insert all the missing peers
          Enum.each(swarm_data, fn peer -> :ets.insert_new(swarm, peer) end)
        end)
      :error -> :ok
    end

    Logger.notice("backup restored")
    ExTracker.Cmd.show_swarm_count()
    ExTracker.Cmd.show_peer_count()

    :ok
  end
end
