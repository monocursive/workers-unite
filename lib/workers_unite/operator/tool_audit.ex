defmodule WorkersUnite.Operator.ToolAudit do
  @moduledoc """
  Schema for operator tool invocation audit records.

  Every tool call made through the operator API is logged here for
  observability and compliance. Rows are insert-only.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "operator_tool_audits" do
    field :tool_name, :string
    field :arguments_summary, :map
    field :result_status, :string
    field :result_ref, :string
    field :client_name, :string

    belongs_to :user, WorkersUnite.Accounts.User
    belongs_to :token, WorkersUnite.Operator.AccessToken

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for inserting an audit record.
  """
  def changeset(audit, attrs) do
    audit
    |> cast(attrs, [
      :tool_name,
      :arguments_summary,
      :result_status,
      :result_ref,
      :client_name,
      :user_id,
      :token_id
    ])
    |> validate_required([:tool_name, :result_status])
  end
end
