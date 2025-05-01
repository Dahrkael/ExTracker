defmodule ExTracker.JsonFileConfigProvider do
  @behaviour Config.Provider
  require Logger

  @impl true
  def init(opts) do
    Keyword.get(opts, :file, "config/extracker.json")
  end

  @impl true
  def load(config, file_path) do
    Logger.info("loading config from: #{file_path}")

    case File.read(file_path) do
      {:ok, contents} ->
        case JSON.decode(contents) do
          {:ok, json_config} ->
            merge_config(config, json_config)
          {:error, err} ->
            Logger.error("error parsing '#{file_path}': #{inspect(err)}")
            config
        end
      {:error, err} ->
        Logger.error("error reading '#{file_path}': #{inspect(err)}")
        config
    end
  end

  defp merge_config(existing_conf, json_conf) do
    Enum.reduce(json_conf, existing_conf, fn {app, confs}, acc ->
      app_atom = String.to_atom(app)
      app_confs = for {k, v} <- confs, into: [], do: {String.to_atom(k), v}
      Keyword.put(acc, app_atom, app_confs)
    end)
  end
end
