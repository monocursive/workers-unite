defmodule WorkersUniteWeb.OperatorMCP.Tools.PublishComment do
  @moduledoc """
  Publishes a comment on a proposal or intent using the node's Vault identity.
  The operator's user_id is recorded in the payload for audit purposes.
  """

  @behaviour WorkersUniteWeb.MCP.Tool

  alias WorkersUnite.{Event, EventStore, Identity}
  alias WorkersUniteWeb.MCP.Tools.Helpers

  @impl true
  def definition do
    %{
      "name" => "wu_publish_comment",
      "description" =>
        "Publishes a comment on a proposal or intent. The comment is signed by the " <>
          "node's Vault identity with the operator's user ID recorded for audit.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["body"],
        "properties" => %{
          "body" => %{
            "type" => "string",
            "description" => "Comment text"
          },
          "proposal_ref" => %{
            "type" => "string",
            "description" => "Hex-encoded event ref of the proposal to comment on"
          },
          "repo_id" => %{
            "type" => "string",
            "description" => "Hex-encoded repository ID for scoping"
          },
          "file" => %{
            "type" => "string",
            "description" => "File path for inline comments"
          },
          "line" => %{
            "type" => "integer",
            "description" => "Line number for inline comments"
          }
        }
      }
    }
  end

  @impl true
  def call(%{"body" => body} = params, context) do
    keypair = Identity.Vault.keypair()

    payload =
      %{"body" => body, "operator_user_id" => context.user_id}
      |> maybe_put("proposal_ref", params["proposal_ref"])
      |> maybe_put("file", params["file"])
      |> maybe_put("line", params["line"])

    scope = resolve_scope(params)
    opts = if scope, do: [scope: scope], else: []

    case Event.new(:comment_added, keypair, payload, opts) do
      {:ok, event} ->
        case EventStore.append(event) do
          {:ok, stored} ->
            {:ok, %{event_ref: Event.ref(stored)}}

          {:error, _} = error ->
            error
        end

      {:error, _} = error ->
        error
    end
  end

  def call(_params, _context), do: {:error, :invalid_params}

  # Operator events are signed with node Vault keypair. In federation, these are
  # attributable to the node, not individual operators. Per-operator Ed25519 keys
  # are a future enhancement.

  defp resolve_scope(%{"proposal_ref" => proposal_ref}) when is_binary(proposal_ref) do
    case Helpers.fetch_proposal(proposal_ref) do
      {:ok, proposal} -> proposal.scope
      {:error, _} -> nil
    end
  end

  defp resolve_scope(%{"repo_id" => repo_id_hex}) when is_binary(repo_id_hex) do
    case Base.decode16(repo_id_hex, case: :mixed) do
      {:ok, binary} -> {:repo, binary}
      :error -> nil
    end
  end

  defp resolve_scope(_params), do: nil

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
