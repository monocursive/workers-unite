defmodule WorkersUnite.Control.JobRegistry do
  @moduledoc """
  Local registry for active job runner processes.
  """

  def child_spec(opts) do
    Registry.child_spec(Keyword.merge([keys: :unique, name: __MODULE__], opts))
  end
end
