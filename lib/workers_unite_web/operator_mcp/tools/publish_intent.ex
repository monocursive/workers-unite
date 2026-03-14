defmodule WorkersUniteWeb.OperatorMCP.Tools.PublishIntent do
  @moduledoc """
  Publishes a new intent to a repository using the node's Vault identity.
  The operator's user_id is recorded in the payload for audit purposes.
  """

  @behaviour WorkersUniteWeb.MCP.Tool

  alias WorkersUnite.{Identity, Repository}
  alias WorkersUniteWeb.MCP.Tools.Helpers

  @impl true
  def definition do
    %{
      "name" => "wu_publish_intent",
      "description" =>
        "Publishes a new intent (work item) to a repository. The intent is signed " <>
          "by the node's Vault identity with the operator's user ID recorded for audit.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["repo_id", "title"],
        "properties" => %{
          "repo_id" => %{
            "type" => "string",
            "description" => "Hex-encoded repository ID"
          },
          "title" => %{
            "type" => "string",
            "description" => "Short title describing the intent"
          },
          "description" => %{
            "type" => "string",
            "description" => "Detailed description of the work to be done"
          },
          "priority" => %{
            "type" => "number",
            "description" => "Priority level (higher = more urgent)"
          },
          "tags" => %{
            "type" => "array",
            "items" => %{"type" => "string"},
            "description" => "Tags for categorization"
          },
          "constraints" => %{
            "type" => "object",
            "description" => "Constraints on how the intent should be fulfilled"
          },
          "affected_paths" => %{
            "type" => "array",
            "items" => %{"type" => "string"},
            "description" => "File paths affected by this intent"
          }
        }
      }
    }
  end

  @impl true
  def call(%{"repo_id" => repo_id_hex, "title" => _title} = params, context) do
    with {:ok, repo_id_binary} <- Helpers.decode_repo_id(repo_id_hex) do
      keypair = Identity.Vault.keypair()

      payload =
        params
        |> Map.drop(["repo_id"])
        |> Map.put("operator_user_id", context.user_id)

      case Repository.publish_intent(repo_id_binary, keypair, payload) do
        {:ok, event} ->
          {:ok,
           %{
             event_ref: WorkersUnite.Event.ref(event),
             repo_id: repo_id_hex,
             title: params["title"]
           }}

        {:error, _} = error ->
          error
      end
    end
  catch
    :exit, _reason -> {:error, :repo_not_found}
  end

  # Operator events are signed with node Vault keypair. In federation, these are
  # attributable to the node, not individual operators. Per-operator Ed25519 keys
  # are a future enhancement.

  def call(_params, _context), do: {:error, :invalid_params}
end
