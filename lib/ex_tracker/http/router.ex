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
  plug ExTracker.HTTP.MultiParamParser
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
              case Map.fetch(conn.assigns[:multi_query_params], "info_hash") do
                :error -> # only malformed queries should fall here
                  ExTracker.Processors.Scrape.process(conn.remote_ip, conn.query_params)
                {:ok, [_hash]} -> # just one hash, may fail so needs special handle
                  ExTracker.Processors.Scrape.process(conn.remote_ip, conn.query_params)
                {:ok, list} -> # multiple hashes in one request
                  # TODO use chunked response
                  successes =
                    list
                    # process each info_hash on its own
                    |> Enum.map(fn hash ->
                      params = %{conn.query_params | "info_hash" => hash}
                      case ExTracker.Processors.Scrape.process(conn.remote_ip, params) do
                        {:ok, response} ->
                          {:ok, byte_hash} = ExTracker.Utils.validate_hash(hash)
                          %{byte_hash => response}
                        {:error, _response} -> nil
                      end
                    end)
                    # discard failed requests
                    |> Enum.reject(&(&1 == nil))
                    # combine the rest into one map
                    |> Enum.reduce( %{}, fn success, acc ->
                      Map.merge(acc, success)
                    end)

                    # return a failure reason is all hashes failed to process
                    case Kernel.map_size(successes) do
                      0 ->
                        {400, %{"failure reason" => "all requested hashes failed to be scraped"}}
                      _ ->
                        #  wrap the map as per BEP 48
                        {200, ExTracker.Types.ScrapeResponse.generate_success_http_envelope(successes)}
                    end
              end
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
      code when code in 200..299 -> :success
      code when code in 400..499 -> :failure
      code when code in 500..599 -> :error
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
