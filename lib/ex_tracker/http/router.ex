defmodule ExTracker.HTTP.Router do
  use Plug.Router
  if Mix.env == :dev, do: use Plug.Debugger

  @assets_folder Application.app_dir(:extracker, "priv/static/assets")

  plug ExTracker.HTTP.HandleReverseProxy
  plug Plug.Logger
  plug ExTracker.Telemetry.Plug
  plug Plug.Static, at: "/assets", from: @assets_folder
  plug :match
  #plug Plug.Parsers, parsers: [:urlencoded, :multipart], pass: ["*/*"], validate_utf8: false
  plug Plug.Parsers, parsers: [], pass: ["text/html"], validate_utf8: false
  plug :dispatch

  # client announcements
  get "/announce" do
    {status, result} = case check_allowed_useragent(conn) do
      true ->
        ExTracker.Processors.Announce.process(conn.remote_ip, conn.query_params)
      false ->
        {403, %{ "failure reason" => "User-Agent not allowed"}}
    end

    # bencoded response
    response = result |> Bento.encode!() |> IO.iodata_to_binary()

    # send telemetry about this request
    send_telemetry(conn.remote_ip, "announce", status, byte_size(response))

    conn
    |> put_resp_content_type("application/octet-stream", nil)
    #|> put_resp_content_type("text/plain", nil)
    |> put_resp_header("cache-control", "no-cache")
    |> send_resp(200, response)

  end

  get "/scrape" do
    {status, result} =
      case Application.get_env(:extracker, :scrape_enabled) do
        true ->
          case check_allowed_useragent(conn) do
            true ->
              # TODO scrapes are supposed to allow multiple 'info_hash' keys to be present to scrape more than one torrent at a time
              # but apparently the standard requires those keys to have '[]' appended to be treated as a list, otherwise they get overwritten
              # this probably needs a custom query_string parser at the router level
              ExTracker.Processors.Scrape.process(conn.remote_ip, conn.query_params)
            false ->
              {403, %{ "failure reason" => "User-Agent not allowed"}}
          end
      _ ->
        {404, %{"failure reason" => "scraping is disabled"}}
    end

    # bencoded response
    response = result |> Bento.encode!() |> IO.iodata_to_binary()

    # send telemetry about this request
    send_telemetry(conn.remote_ip, "scrape", status, byte_size(response))

    conn
    |> put_resp_content_type("application/octet-stream", nil)
    #|> put_resp_content_type("text/plain", nil)
    |> put_resp_header("cache-control", "no-cache")
    |> send_resp(200, response)
  end

  match _ do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, ExTracker.web_about())
  end

  defp send_telemetry(ip, action, status, response_size) do
    # send outcoming bandwidth and the request result here instead of ExTracker.Telemetry.Plug
    # because we don't know the result and response size until the very end
    endpoint = "http"

    result = case status do
      :ok -> :success
      :error -> :failure
      200..299 -> :success
      400..499 -> :failure
      500..599 -> :error
    end

    family = case tuple_size(ip) do
      4 -> "inet"
      8 -> "inet6"
    end

    :telemetry.execute([:extracker, :request, result], %{}, %{endpoint: endpoint, action: action, family: family})
    :telemetry.execute([:extracker, :bandwidth, :out], %{value: response_size})
  end

  defp get_useragent(conn) do
    conn |> Plug.Conn.get_req_header("user-agent") |> List.first()
  end

  defp check_allowed_useragent(conn) do
    case Application.get_env(:extracker, :restrict_useragents, false) do
      "whitelist" -> ExTracker.Accesslist.contains(:whitelist_useragents, get_useragent(conn))
      "blacklist" -> !ExTracker.Accesslist.contains(:blacklist_useragents, get_useragent(conn))
      _ -> true
    end
  end
end
