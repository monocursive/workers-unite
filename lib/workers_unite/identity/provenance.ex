defmodule WorkersUnite.Identity.Provenance do
  @moduledoc """
  Tracks the origin and capabilities of an AI agent in the WorkersUnite network.
  """

  @valid_kinds [:coder, :reviewer, :orchestrator, :ci_runner, :custom]

  @enforce_keys [:agent_id, :kind, :created_at]
  defstruct [
    :agent_id,
    :kind,
    :created_at,
    spawner: nil,
    model: nil,
    model_version: nil,
    capabilities: [],
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          agent_id: binary(),
          kind: :coder | :reviewer | :orchestrator | :ci_runner | :custom,
          spawner: binary() | nil,
          model: String.t() | nil,
          model_version: String.t() | nil,
          capabilities: [atom()],
          metadata: map(),
          created_at: integer()
        }

  @doc """
  Creates a new Provenance struct from a keyword list or map.

  Returns `{:ok, %Provenance{}}` or `{:error, reason}`.
  """
  def new(attrs) when is_list(attrs) do
    attrs |> Map.new() |> new()
  end

  def new(%{} = attrs) do
    with :ok <- validate_kind(attrs[:kind] || attrs["kind"]) do
      {:ok, struct!(__MODULE__, attrs)}
    end
  rescue
    e in ArgumentError -> {:error, e.message}
  end

  defp validate_kind(kind) when kind in @valid_kinds, do: :ok
  defp validate_kind(kind), do: {:error, "invalid kind: #{inspect(kind)}"}

  @doc """
  Returns the list of valid agent kinds.
  """
  def valid_kinds, do: @valid_kinds
end
