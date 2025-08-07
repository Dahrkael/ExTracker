defmodule ExTracker.Integrations.Arcadia.Router do
  use Plug.Router
  require Logger

  alias ExTracker.Integrations.Arcadia

  if Mix.env == :dev, do: use Plug.Debugger
  plug Plug.Logger
  plug :match
  #plug Plug.Parsers, parsers: [:urlencoded, :multipart], pass: ["*/*"], validate_utf8: false
  #plug Plug.Parsers, parsers: [], pass: ["text/html"], validate_utf8: false
  plug Plug.Parsers, parsers: [:json], pass: ["application/json"], json_decoder: Jason
  plug :dispatch

  # add new hashes to the Hashes Whitelist
  post "/torrent" do
    {status, response} = case conn.body_params do
      # Jason returns a '_json' keyed map when theres no root json object
      %{"_json" => torrents} = params when map_size(params) == 1 and is_list(torrents) ->
        {added, failed} = Enum.reduce(torrents, {0, 0}, fn
            %{"created_at" => created_at, "id" => id, "info_hash" => info_hash}, {a, f} ->
              case Arcadia.add_torrent(info_hash, id, created_at) do
                :ok -> {a + 1, f}
                :error -> {a, f + 1}
              end
            wrong_data, {a, f} ->
              Logger.warning("[integration][arcadia] invalid data format for new torrent: #{inspect(wrong_data)}")
              {a, f + 1}
        end)

        {200, Jason.encode!(%{added: added, failed: failed})}
      what ->
        IO.inspect(what)
        {400, ~s({"error": "body must be a JSON list"})}
    end

    conn
    |> put_resp_content_type("application/json", nil)
    |> put_resp_header("cache-control", "no-cache")
    |> send_resp(status, response)

  end

  # remove existing hashes from the Hashes Whitelist
  delete "/torrent" do
    {status, response} = case conn.body_params do
      # Jason returns a '_json' keyed map when theres no root json object
      %{"_json" => torrents} = params when map_size(params) == 1 and is_list(torrents) ->
        {removed, failed} = Enum.reduce(torrents, {0, 0}, fn info_hash, {r, f} ->
          case Arcadia.remove_torrent(info_hash) do
            :ok -> {r + 1, f}
            :error -> {r, f + 1}
          end
        end)

        {200, Jason.encode!(%{removed: removed, failed: failed})}
      _ ->
        {400, ~s({"error": "body must be a JSON list"})}
    end

    conn
    |> put_resp_content_type("application/json", nil)
    |> put_resp_header("cache-control", "no-cache")
    |> send_resp(status, response)

  end

  match _ do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(404, "Not Found")
  end
end
