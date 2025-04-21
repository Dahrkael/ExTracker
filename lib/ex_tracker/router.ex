defmodule ExTracker.Router do
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
    {status, response} = ExTracker.Processors.Announce.process(conn.remote_ip, conn.query_params)

    conn
    |> put_resp_content_type("application/octet-stream", nil)
    #|> put_resp_content_type("text/plain", nil)
    |> put_resp_header("cache-control", "no-cache")
    |> send_resp(status, response)

  end

  get "/scrape" do
    conn
    |> put_resp_content_type("text/plain")
    |> put_resp_header("cache-control", "no-cache")
    |> send_resp(404, "<h1>Not implemented</h1>")
  end

  get "/about" do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, ExTracker.about())
  end

  match _ do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp( 404, "<h1>Not Found</h1>")
  end
end
