defmodule ExTracker.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false
require Logger

  use Application
  alias ExTracker.Utils

  @impl true
  def start(_type, _args) do
    # override the configuration with whatever environment variables are set
    Extracker.Config.SystemEnvironment.load()

    # print out the configuration to be sure what values are being used after reading everything
    IO.puts(ExTracker.console_about())
    print_current_config()

    # check before spawning anything if the provided bind ips are valid
    if !check_ipv4() or !check_ipv6() do
      # the user should fix the config instead of trying to boot a erroneous server
      exit(:misconfigured_address)
    end

    required_children = [
      { ExTracker.SwarmFinder, {}},
      { ExTracker.SwarmCleaner, {}},
      { ExTracker.Backup, {}}
    ]

    ipv4_optional_children = case Application.get_env(:extracker, :ipv4_enabled) do
      true ->
        Logger.notice("IPv4 enabled on address #{inspect(Application.get_env(:extracker, :ipv4_bind_address))}")
        []
          ++ get_http_children(:inet)
          ++ get_https_children(:inet)
          ++ get_udp_children(:inet)
      _ -> []
    end

    ipv6_optional_children = case Application.get_env(:extracker, :ipv6_enabled) do
      true ->
        Logger.notice("IPv6 enabled on address #{inspect(Application.get_env(:extracker, :ipv6_bind_address))}")
        []
          ++ get_http_children(:inet6)
          ++ get_https_children(:inet6)
          ++ get_udp_children(:inet6)
      _ -> []
    end

    children = Enum.concat([required_children, ipv4_optional_children, ipv6_optional_children])

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ExTracker.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp print_current_config() do
    config =
      Application.get_all_env(:extracker)
      |> Enum.sort_by(fn {key, _value} -> key end)
      |> Enum.map(fn {key, value} -> "#{Atom.to_string(key)}: #{inspect(value)}" end)
      |> Enum.join("\n")

    IO.puts(["configuration to be used:\n"] ++ config)
  end

  defp check_ipv4() do
    case Application.get_env(:extracker, :ipv4_enabled, false) do
      true ->
        case Application.get_env(:extracker, :ipv4_bind_address) do
          nil ->
            Logger.error("ipv4 mode is enabled but theres no configured ipv4 bind address")
            false
          addr ->
            case :inet.parse_ipv4_address(to_charlist(addr)) do
              {:ok, _parsed} ->
                true
              {:error, :einval} ->
                Logger.error("configured ipv4 bind address is not a valid v4 address")
                false
          end
      end
      _ -> true
    end
  end

  defp check_ipv6() do
    case Application.get_env(:extracker, :ipv6_enabled, false) do
      true ->
        case Application.get_env(:extracker, :ipv6_bind_address) do
          nil ->
            Logger.error("ipv6 mode is enabled but theres no configured ipv6 bind address")
            false
          addr ->
            case :inet.parse_ipv6_address(to_charlist(addr)) do
              {:ok, _parsed} ->
                true
              {:error, :einval} ->
                Logger.error("configured ipv6 bind address is not a valid v6 address")
                false
          end
      end
      _ -> true
    end
  end

  defp get_http_children(family) do
    case Application.get_env(:extracker, :http_enabled) do
      true ->
        ip = case family do
          :inet -> Utils.get_configured_ipv4()
          :inet6 -> Utils.get_configured_ipv6()
        end
        port = Application.get_env(:extracker, :http_port)

        http_spec = Supervisor.child_spec(
          {Plug.Cowboy, scheme: :http, plug: ExTracker.HTTP.Router, options: [
            net: family,
            ip: ip,
            port: port,
            compress: true,
            ref: "http_router_#{to_string(family)}",
            dispatch: dispatch(),
            transport_options: [
              num_acceptors: 100,
              max_connections: 100_000,
            ]
          ] ++ (if family == :inet6, do: [ipv6_v6only: true], else: [])
          },
          id: :"http_supervisor_#{family}"
        )

        Logger.notice("HTTP mode enabled on port #{port}")
        #if Application.ensure_started(:ranch) do
        #  IO.inspect(:ranch.info(http_spec.id), label: "HTTP info")
        #end

        [http_spec]
      false ->
        Logger.notice("HTTP mode disabled")
        []
    end
  end

  defp get_https_children(family) do
    case Application.get_env(:extracker, :https_enabled) do
      true ->
        ip = case family do
          :inet -> Utils.get_configured_ipv4()
          :inet6 -> Utils.get_configured_ipv6()
        end
        port = Application.get_env(:extracker, :https_port)
        keyfile = Application.get_env(:extracker, :https_keyfile, "") |> Path.expand()

        https_spec = Supervisor.child_spec(
          {Plug.Cowboy, scheme: :https, plug: ExTracker.HTTP.Router, options: [
            net: family,
            ip: ip,
            port: port,
            keyfile: keyfile,
            compress: true,
            ref: "https_router_#{to_string(family)}",
            dispatch: dispatch(),
            transport_options: [
              num_acceptors: 100,
              max_connections: 100_000,
            ]
          ] ++ (if family == :inet6, do: [ipv6_v6only: true], else: [])
          },
          id: :"https_supervisor_#{family}"
        )

        Logger.notice("HTTPS mode enabled on port #{port}")
        #if Application.ensure_started(:ranch) do
        #  IO.inspect(:ranch.info(https_spec.id), label: "HTTPS info")
        #end

        [https_spec]
      false ->
        Logger.notice("HTTPS mode disabled")
        []
    end
  end

  defp get_udp_children(family) do
    case Application.get_env(:extracker, :udp_enabled) do
      true ->
        n = case Application.get_env(:extracker, :udp_routers, -1) do
          -1 -> 1..System.schedulers_online()
          n -> 1..n
        end

        port = Application.get_env(:extracker, :udp_port)
        Logger.notice("UDP mode enabled on port #{port} using #{Enum.count(n)} routers")

        Enum.map(n, fn index ->
          Supervisor.child_spec(
            {ExTracker.UDP.Supervisor, [family: family, port: port, index: index - 1]},
            id: :"udp_supervisor_#{family}_#{index}")
        end)

      false ->
        Logger.notice("UDP mode disabled")
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
