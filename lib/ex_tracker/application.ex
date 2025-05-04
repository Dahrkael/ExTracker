defmodule ExTracker.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false
require Logger

  use Application

  @impl true
  def start(_type, args) do
    # config is loaded from config.exs first then the command line can override whats needed here
    ExTracker.CLIReader.read(args)

    # print out the configuration to be sure what values are being used after reading everything
    IO.puts(ExTracker.console_about())
    print_current_config()

    required_children = [
      { ExTracker.SwarmFinder, {}}
    ]

    optional_children = [] ++ get_http_children() ++ get_https_children() ++ get_udp_children()
    children = Enum.concat([required_children, optional_children])

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ExTracker.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp get_http_children() do
    case Application.get_env(:extracker, :http_enabled) do
      true ->
        http_spec = Plug.Cowboy.child_spec(scheme: :http, plug: ExTracker.HTTP.Router, options: [
          port: Application.get_env(:extracker, :http_port),
          dispatch: dispatch()
        ])

        Logger.info("HTTP mode enabled")
        #if Application.ensure_started(:ranch) do
        #  IO.inspect(:ranch.info(http_spec.id), label: "HTTP info")
        #end

        [http_spec]
      false ->
        Logger.info("HTTP mode disabled")
        []
    end
  end

  defp print_current_config() do
    config =
      Application.get_all_env(:extracker)
      |> Enum.sort_by(fn {key, _value} -> key end)
      |> Enum.map(fn {key, value} -> "#{Atom.to_string(key)}: #{inspect(value)}" end)
      |> Enum.join("\n")

    IO.puts(["configuration to be used:\n"] ++ config)
  end

  defp get_https_children() do
    case Application.get_env(:extracker, :https_enabled) do
      true ->
        https_spec = Plug.Cowboy.child_spec(scheme: :https, plug: ExTracker.HTTP.Router, options: [
          port: Application.get_env(:extracker, :https_port),
          keyfile: "",
          dispatch: dispatch()
        ])

        Logger.info("HTTPS mode enabled")
        #if Application.ensure_started(:ranch) do
        #  IO.inspect(:ranch.info(https_spec.id), label: "HTTPS info")
        #end

        [https_spec]
      false ->
        Logger.info("HTTPS mode disabled")
        []
    end
  end

  defp get_udp_children() do
    case Application.get_env(:extracker, :udp_enabled) do
      true ->
        n = case Application.get_env(:extracker, :udp_routers, -1) do
          -1 -> 1..System.schedulers_online()
          n -> 1..n
        end

        Logger.info("UDP mode enabled using #{Enum.count(n)} routers")

        Enum.map(n, fn index ->
          Supervisor.child_spec(
            {ExTracker.UDP.Supervisor, [port: Application.get_env(:extracker, :udp_port), index: index - 1]},
            id: :"udp_supervisor_#{index}")
        end)

      false ->
        Logger.info("UDP mode disabled")
        []
    end
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
