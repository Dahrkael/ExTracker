defmodule ExTracker.Telemetry.Plug do
  @behaviour Plug

  def init(opts), do: opts

  def call(conn, _opts) do
    start_time = System.monotonic_time(:microsecond)

    Plug.Conn.register_before_send(conn, fn conn ->
      elapsed = System.monotonic_time(:microsecond) - start_time

      # incoming bandwidth
      size = estimate_request_size(conn)
      :telemetry.execute([:extracker, :bandwidth, :in], %{value: size})

      # request processing time
      endpoint = "http"
      family = case tuple_size(conn.remote_ip) do
        4 -> "inet"
        8 -> "inet6"
      end

      action = case conn.request_path do
        "/announce" -> "announce"
        "/scrape" -> "scrape"
        _ -> nil
      end

      if action != nil do
        :telemetry.execute([:extracker, :request], %{processing_time: elapsed}, %{endpoint: endpoint, action: action, family: family})
      end

      conn
    end)
  end

  defp estimate_request_size(conn) do
    method = conn.method
    path = conn.request_path

    request_line_size = byte_size("#{method} #{path}") + 10 # "HTTP/1.1" and "\r\n"

    headers_size =
      conn.req_headers
      |> Enum.map(fn {k, v} -> byte_size(k) + byte_size(v) + 4 end)  # ": " and "\r\n"
      |> Enum.sum()

    request_line_size + headers_size + 2 # "\r\n"
  end
end
