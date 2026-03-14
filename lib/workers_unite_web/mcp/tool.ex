defmodule WorkersUniteWeb.MCP.Tool do
  @moduledoc """
  Behaviour for WorkersUnite MCP tool handlers.
  """

  @callback definition() :: map()
  @callback call(map(), map()) :: {:ok, term()} | {:error, term()}
end
