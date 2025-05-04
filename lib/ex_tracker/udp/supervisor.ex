defmodule ExTracker.UDP.Supervisor do
  use Supervisor

  @doc """
  starts the UDP Supervisor that integrates the UDP Router and the Supervisor for its tasks
  """
  def start_link(args \\ []) do
    index = Keyword.get(args, :index, 0)
    Supervisor.start_link(__MODULE__, args, name: :"udp_supervisor_#{index}")
  end

  @impl true
  def init(args) do
    index = Keyword.get(args, :index, 0)
    port = Keyword.get(args, :port)

    children = [
      # Task Supervisor for concurrently processing incoming UDP messages
      {Task.Supervisor, name: get_task_supervisor_name(index)},
      # the UDP Router that listens for UDP messages
      {ExTracker.UDP.Router, index: index, port: port, name: get_router_name(index)}
    ]

    # if the router fails the tasks wont be able to use the socket so restart them all
    Supervisor.init(children, strategy: :one_for_all)
  end

  def get_router_name(index) do
    :"udp_router_#{index}"
  end

  def get_task_supervisor_name(index) do
    :"udp_task_supervisor_#{index}"
  end
end
