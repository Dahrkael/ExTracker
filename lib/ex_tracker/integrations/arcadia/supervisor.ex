defmodule ExTracker.Integrations.Arcadia.Supervisor do
  use Supervisor

  def start_link(args \\ []) do
    Supervisor.start_link(__MODULE__, args)
  end

  @impl true
  def init(args) do
    ip = Keyword.get(args, :ip)
    port = Keyword.get(args, :port)

    children = [
      {ExTracker.Integrations.Arcadia, {}},
      Supervisor.child_spec(
        {Plug.Cowboy, scheme: :http, plug: ExTracker.Integrations.Arcadia.Router, options: [
            ip: ip,
            port: port,
            compress: true,
            ref: "arcadia_http_router",
            transport_options: [
              num_acceptors: 10
            ]
          ]
          },
          id: :arcadia_http_supervisor
      )
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
