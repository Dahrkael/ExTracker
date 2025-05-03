defmodule ExTracker.UDP.Supervisor do
  use Supervisor

  @doc """
  starts the UDP Supervisor that integrates the UDP Router and the Supervisor for its tasks
  """
  def start_link(args \\ []) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(args) do
    port = Keyword.get(args, :port)

    children = [
      # Task Supervisor for concurrently processing incoming UDP messages
      {Task.Supervisor, name: ExTracker.UDP.TaskSupervisor},
      # the UDP Router that listens for UDP messages
      {ExTracker.UDP.Router, port}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
