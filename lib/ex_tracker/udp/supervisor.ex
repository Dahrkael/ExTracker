defmodule ExTracker.UDP.Supervisor do
  use Supervisor

  @doc """
  starts the UDP Supervisor that integrates the UDP Router and the Supervisor for its tasks
  """
  def start_link(args \\ []) do
    index = Keyword.get(args, :index, 0)
    ipversion = Keyword.get(args, :ipversion)
    Supervisor.start_link(__MODULE__, args, name: :"udp_supervisor_#{ipversion}_#{index}")
  end

  @impl true
  def init(args) do
    index = Keyword.get(args, :index, 0)
    port = Keyword.get(args, :port)
    ipversion = Keyword.get(args, :ipversion)

    children = [
      # Task Supervisor for concurrently processing incoming UDP messages
      {Task.Supervisor, name: get_task_supervisor_name(index, ipversion)},
      # the UDP Router that listens for UDP messages
      {ExTracker.UDP.Router, index: index, ipversion: ipversion, port: port, name: get_router_name(index, ipversion)}
    ]

    # if the router fails the tasks wont be able to use the socket so restart them all
    Supervisor.init(children, strategy: :one_for_all)
  end

  def get_router_name(index, ipversion) do
    :"udp_router_#{ipversion}_#{index}"
  end

  def get_task_supervisor_name(index, ipversion) do
    :"udp_task_supervisor_#{ipversion}_#{index}"
  end
end
