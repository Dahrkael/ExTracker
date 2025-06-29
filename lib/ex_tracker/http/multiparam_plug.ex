defmodule ExTracker.HTTP.MultiParamParser do

  def init(opts), do: opts

  def call(conn, _opts) do
    #URI.query_decoder("foo=1&bar=2") |> Enum.to_list()
    multi_params =
      conn.query_string
      |> URI.query_decoder()
      |> Enum.to_list()
      |> Enum.group_by(fn {k, _v} -> k end, fn {_k, v} -> v end)

    Plug.Conn.assign(conn, :multi_query_params, multi_params)
  end
end
