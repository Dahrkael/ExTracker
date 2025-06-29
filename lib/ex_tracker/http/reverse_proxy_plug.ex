defmodule ExTracker.HTTP.HandleReverseProxy do
require Logger

  @behaviour Plug

  def init(opts) do
    case Application.get_env(:extracker, :reverse_proxy_address, "") do
      nil -> [] # no proxy set
      "" -> [] # no proxy set
      address ->
        case :inet.parse_address(address) do
         {:ok, proxy_ip} ->
          Logger.notice("Reverse Proxy address set to #{proxy_ip}")
          [proxy: proxy_ip]
         _ ->
          Logger.error("specified reverse proxy address is not a valid ip")
          []
       end
    end

    opts
  end

  def call(conn, opts) do
    # handle proxy headers only if a reverse proxy is specified in the config
    case Keyword.get(opts, :proxy) do
      nil -> conn
      proxy_ip -> handle_proxy(conn, proxy_ip)
    end
  end

  defp handle_proxy(conn, proxy_ip) do
    # the remote ip must match the specified proxy otherwise ignore it
    case conn.remote_ip do
      ^proxy_ip ->
        # TODO throw a warning/error if the reverse proxy doesnt add the header?
        header = Plug.Conn.get_req_header(conn, "x-forwarded-for") |> List.first()
        case parse_forwarded_ip(header) do
          nil -> conn
          real_ip -> %{conn | remote_ip: real_ip}
        end
      _ -> conn
    end
  end

  defp parse_forwarded_ip(nil), do: nil
  defp parse_forwarded_ip(header) do
    header
    |> String.split(",", trim: true)
    |> List.first()
    |> String.trim()
    |> :inet.parse_address()
    |> case do
         {:ok, ip} -> ip
         _ -> nil
       end
  end
end
