defmodule ExTracker.Telemetry.Router do
  use Plug.Router
  if Mix.env == :dev, do: use Plug.Debugger

  @assets_folder Application.app_dir(:extracker, "priv/static/assets")

  plug Plug.Logger
  plug Plug.Static, at: "/assets", from: @assets_folder
  plug :match
  #plug Plug.Parsers, parsers: [:urlencoded, :multipart], pass: ["*/*"], validate_utf8: false
  plug Plug.Parsers, parsers: [], pass: ["text/html"], validate_utf8: false
  plug :dispatch

  # basic telemetry
  get "/tracker-stats.html" do
    response = ExTracker.Telemetry.render_tracker_stats_html()
    conn
    |> put_resp_content_type("text/html")
    |> put_resp_header("cache-control", "no-cache")
    |> send_resp(200, response)

  end

  # prometheus scrape
  get "/prometheus" do
    metrics = TelemetryMetricsPrometheus.Core.scrape()

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, metrics)
  end

  match _ do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, ExTracker.web_about())
  end
end
