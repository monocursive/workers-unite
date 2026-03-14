defmodule Forgelet.Control.NodeRegistry do
  @moduledoc """
  Local registry for control-plane node processes.
  """

  def child_spec(opts) do
    Registry.child_spec(Keyword.merge([keys: :unique, name: __MODULE__], opts))
  end
end
