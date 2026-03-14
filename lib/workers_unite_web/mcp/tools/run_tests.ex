defmodule WorkersUniteWeb.MCP.Tools.RunTests do
  @behaviour WorkersUniteWeb.MCP.Tool

  alias WorkersUnite.Agent.Workspace
  alias WorkersUniteWeb.MCP.Tools.Helpers

  @impl true
  def definition do
    %{
      "name" => "workers_unite_run_tests",
      "description" => "Runs tests in a repo-local session checkout.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["repo_id"],
        "properties" => %{
          "repo_id" => %{"type" => "string"},
          "test_path" => %{"type" => "string"},
          "command" => %{"type" => "array"}
        }
      }
    }
  end

  @impl true
  def call(%{"repo_id" => repo_id} = params, %{working_dir: working_dir}) do
    with {:ok, repo_id_binary} <- Helpers.decode_repo_id(repo_id),
         {:ok, repo_path} <- Workspace.ensure_repo_checkout(working_dir, repo_id_binary),
         {:ok, argv} <- command_args(params) do
      {stdout, exit_code} = System.cmd(hd(argv), tl(argv), cd: repo_path, stderr_to_stdout: true)
      {:ok, %{exit_code: exit_code, stdout: stdout, stderr: ""}}
    end
  end

  def call(_params, _context), do: {:error, :invalid_params}

  defp command_args(%{"command" => [cmd | _] = argv}) when is_binary(cmd), do: {:ok, argv}

  defp command_args(%{"test_path" => test_path}) when is_binary(test_path) do
    {:ok, default_test_command() ++ [test_path]}
  end

  defp command_args(_params), do: {:ok, default_test_command()}

  defp default_test_command do
    Application.get_env(:workers_unite, :default_test_command, ["mix", "test"])
  end
end
