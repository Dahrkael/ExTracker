defmodule ExTracker.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, args) do
    # config is loaded from config.exs first then the command line can override whats needed here
    ExTracker.CLIReader.read(args)

    http_port = Application.get_env(:extracker, :http_port)

    children = [
      # Starts a worker by calling: ExTracker.Worker.start_link(arg)
      { ExTracker.SwarmFinder, {}},
      { Plug.Cowboy, scheme: :http, plug: ExTracker.Router, options: [ port: http_port, dispatch: dispatch() ] },
      #{ Plug.Cowboy, scheme: :https, plug: ExTracker.Router, options: [ port: 443, dispatch: dispatch() ] }
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ExTracker.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp dispatch() do
    [
      { :_, [
        #{ "/ws", ExTracker.Websocket, [] },
        { :_, Plug.Cowboy.Handler, { ExTracker.Router, [] } }
      ] }
    ]
  end
end
