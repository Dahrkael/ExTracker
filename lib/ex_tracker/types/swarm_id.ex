defmodule ExTracker.Types.SwarmID do

  alias ExTracker.Types.SwarmID

  @enforce_keys [:hash, :table, :type]
  defstruct [:hash, :table, :type]

  @type t :: %__MODULE__{
          hash: binary(),
          table: :ets.tid() | atom(),
          type: :small | :big
        }

  @spec new(hash :: binary(), table :: :ets.tid() | atom(), type :: atom()) :: SwarmID.t()
  def new(hash, table, type) do
    %SwarmID{hash: hash, table: table, type: type}
  end
end
