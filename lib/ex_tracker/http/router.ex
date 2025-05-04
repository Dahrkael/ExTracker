defmodule ExTracker.HTTP.Router do
  use Plug.Router
  if Mix.env == :dev, do: use Plug.Debugger

  @assets_folder Application.app_dir(:extracker, "priv/static/assets")

  plug Plug.Logger
  plug Plug.Static, at: "/assets", from: @assets_folder
  plug :match
  #plug Plug.Parsers, parsers: [:urlencoded, :multipart], pass: ["*/*"], validate_utf8: false
  plug Plug.Parsers, parsers: [], pass: ["text/html"], validate_utf8: false
  plug :dispatch

  # client announcements
  get "/announce" do
    {_status, result} = ExTracker.Processors.Announce.process(conn.remote_ip, conn.query_params)
    # bencoded response
    response = result |> Benx.encode() |> IO.iodata_to_binary()

    conn
    |> put_resp_content_type("application/octet-stream", nil)
    #|> put_resp_content_type("text/plain", nil)
    |> put_resp_header("cache-control", "no-cache")
    |> send_resp(200, response)

  end

  get "/scrape" do
    # TODO scrapes are supposed to allow multiple 'info_hash' keys to be present to scrape more than one torrent at a time
    # but apparently the standard requires those keys to have '[]' appended to be treated as a list, otherwise they get overwritten
    # this probably needs a custom query_string parser at the router level
    {_status, result} = ExTracker.Processors.Scrape.process(conn.remote_ip, conn.query_params)
    # bencoded response
    response = result |> Benx.encode() |> IO.iodata_to_binary()

    conn
    |> put_resp_content_type("application/octet-stream", nil)
    #|> put_resp_content_type("text/plain", nil)
    |> put_resp_header("cache-control", "no-cache")
    |> send_resp(200, response)
  end

  get "/about" do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, ExTracker.web_about())
  end

  match _ do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp( 404, "<h1>Not Found</h1>")
  end
end
