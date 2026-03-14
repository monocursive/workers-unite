defmodule WorkersUniteWeb.OperatorMCP.Tools.DispatchWork do
  @moduledoc """
  Dispatches work to a worker agent by starting an autonomous session.
  Finds an idle agent of the requested kind or spawns a new one.
  """

  @behaviour WorkersUniteWeb.MCP.Tool

  alias WorkersUnite.{Agent, Identity}
  alias WorkersUnite.Operator.Dispatch
  alias WorkersUniteWeb.MCP.Tools.Helpers

  @valid_kinds ["coder", "reviewer", "orchestrator"]

  @impl true
  def definition do
    %{
      "name" => "wu_dispatch_work",
      "description" =>
        "Dispatches work to a worker agent by starting an autonomous session. " <>
          "If no agent_id is specified, finds an idle agent of the requested kind or spawns a new one.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["kind"],
        "properties" => %{
          "kind" => %{
            "type" => "string",
            "enum" => @valid_kinds,
            "description" => "Type of worker agent: coder, reviewer, or orchestrator"
          },
          "agent_id" => %{
            "type" => "string",
            "description" =>
              "Hex-encoded Ed25519 public key of a specific agent. " <>
                "If omitted, an idle agent of the requested kind is selected or spawned."
          },
          "repo_id" => %{
            "type" => "string",
            "description" => "Hex-encoded repository ID for the work context"
          },
          "intent_ref" => %{
            "type" => "string",
            "description" => "Hex-encoded event ref of the intent being worked on"
          },
          "task_description" => %{
            "type" => "string",
            "description" => "Free-text description of the task for the agent"
          }
        }
      }
    }
  end

  @impl true
  def call(%{"kind" => kind} = params, _context) when kind in @valid_kinds do
    with {:ok, agent_id} <- resolve_agent(kind, params),
         session_opts <- build_session_opts(params),
         {:ok, _session_pid, session_token} <- Agent.start_session(agent_id, session_opts) do
      {:ok,
       %{
         agent_fingerprint: Identity.fingerprint(agent_id),
         session_token_prefix: String.slice(session_token, 0, 8),
         status: "session_started",
         kind: kind
       }}
    end
  catch
    :exit, _reason -> {:error, :agent_not_found}
  end

  def call(%{"kind" => kind}, _context) when is_binary(kind) do
    {:error, {:invalid_kind, "must be one of: #{Enum.join(@valid_kinds, ", ")}"}}
  end

  def call(_params, _context), do: {:error, :invalid_params}

  defp resolve_agent(_kind, %{"agent_id" => agent_id_hex}) when is_binary(agent_id_hex) do
    case Base.decode16(agent_id_hex, case: :mixed) do
      {:ok, binary} -> {:ok, binary}
      :error -> {:error, :invalid_agent_id}
    end
  end

  defp resolve_agent(kind, _params) do
    Dispatch.find_or_spawn(kind)
  end

  defp build_session_opts(params) do
    opts = []

    opts =
      case params["repo_id"] do
        nil ->
          opts

        repo_id_hex ->
          case Helpers.decode_repo_id(repo_id_hex) do
            {:ok, binary} -> Keyword.put(opts, :repo_id, binary)
            {:error, _} -> opts
          end
      end

    opts =
      case params["intent_ref"] do
        nil -> opts
        intent_ref -> Keyword.put(opts, :intent_ref, intent_ref)
      end

    case params["task_description"] do
      nil -> opts
      desc -> Keyword.put(opts, :task_description, desc)
    end
  end
end
