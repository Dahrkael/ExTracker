defmodule ExTracker.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, args) do
    # config is loaded from config.exs first then the command line can override whats needed here
    ExTracker.CLIReader.read(args)

    http_enabled = Application.get_env(:extracker, :http_enabled)
    https_enabled = Application.get_env(:extracker, :https_enabled)
    udp_enabled = Application.get_env(:extracker, :udp_enabled)

    required_children = [
      { ExTracker.SwarmFinder, {}}
    ]

    optional_children = [
      http_enabled && { Plug.Cowboy, scheme: :http, plug: ExTracker.HTTP.Router, options: [
        port: Application.get_env(:extracker, :http_port),
        dispatch: dispatch()
      ] },
      https_enabled && { Plug.Cowboy, scheme: :https, plug: ExTracker.HTTP.Router, options: [
        port: Application.get_env(:extracker, :https_port),
        keyfile: "",
        dispatch: dispatch()
      ] },
      udp_enabled && {ExTracker.UDP.Supervisor,
        port: Application.get_env(:extracker, :udp_port)
      }
    ] |> Enum.filter(fn child -> child end)

    children = Enum.concat([required_children, optional_children])

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ExTracker.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp dispatch() do
    [
      { :_, [
        #{ "/ws", ExTracker.Websocket, [] },
        { :_, Plug.Cowboy.Handler, { ExTracker.HTTP.Router, [] } }
      ] }
    ]
  end
end
