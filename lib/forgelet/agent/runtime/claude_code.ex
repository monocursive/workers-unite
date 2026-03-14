defmodule Forgelet.Agent.Runtime.ClaudeCode do
  @moduledoc """
  Claude Code runtime adapter.
  """

  use GenServer

  @behaviour Forgelet.Agent.Runtime

  alias Forgelet.{CredentialStore, ModelRegistry}
  alias Forgelet.Agent.{SessionRegistry, SystemPrompt, Workspace}
  alias ForgeletWeb.MCP.ToolRegistry

  @runtime_name :claude_code

  @impl true
  def start_run(owner_pid, agent_id, kind, opts \\ []) do
    with {:ok, workspace_root} <- Workspace.create_session_root(),
         {:ok, token} <- SessionRegistry.create(agent_id, kind, workspace_root) do
      child_spec =
        {__MODULE__,
         Keyword.merge(opts,
           owner_pid: owner_pid,
           agent_id: agent_id,
           kind: kind,
           workspace_root: workspace_root,
           session_token: token
         )}

      case DynamicSupervisor.start_child(Forgelet.SessionSupervisor, child_spec) do
        {:ok, pid} ->
          {:ok, pid, token}

        {:error, reason} ->
          :ok = SessionRegistry.invalidate(token)
          :ok = Workspace.cleanup(workspace_root)
          {:error, reason}
      end
    end
  end

  @impl true
  def cancel_run(pid) when is_pid(pid) do
    DynamicSupervisor.terminate_child(Forgelet.SessionSupervisor, pid)
  catch
    :exit, _reason -> {:error, :not_found}
  end

  @impl true
  def capabilities do
    %{mode: :cli, tools: [:mcp, :filesystem, :shell]}
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def child_spec(opts) do
    %{
      id: {__MODULE__, Keyword.fetch!(opts, :session_token)},
      start: {__MODULE__, :start_link, [opts]},
      restart: :temporary
    }
  end

  @impl true
  def init(opts) do
    owner_pid = Keyword.fetch!(opts, :owner_pid)
    agent_id = Keyword.fetch!(opts, :agent_id)
    kind = Keyword.fetch!(opts, :kind)
    workspace_root = Keyword.fetch!(opts, :workspace_root)
    session_token = Keyword.fetch!(opts, :session_token)
    timeout_ms = Keyword.get(opts, :timeout_ms, timeout_for(kind))
    task_context = Keyword.get(opts, :task_context)

    config_path = write_mcp_config(session_token)
    prompt = SystemPrompt.build(kind, agent_id, task_context, workspace_root)
    claude_path = Application.get_env(:forgelet, :claude_cli_path, "claude")
    args = build_args(prompt, kind, config_path)
    {launch_path, launch_args} = build_launch_command(claude_path, args, workspace_root)

    port =
      Port.open({:spawn_executable, launch_path}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: launch_args,
        cd: workspace_root,
        env: []
      ])

    timeout_ref = Process.send_after(self(), :session_timeout, timeout_ms)

    {:ok,
     %{
       owner_pid: owner_pid,
       session_token: session_token,
       workspace_root: workspace_root,
       config_path: config_path,
       port: port,
       status: :running,
       output_buffer: [],
       timeout_ref: timeout_ref
     }}
  rescue
    error ->
      {:stop, error}
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    {:noreply, %{state | output_buffer: [state.output_buffer | data]}}
  end

  def handle_info({port, {:exit_status, code}}, %{port: port} = state) do
    session_status = if code == 0, do: :completed, else: :failed
    {:stop, {:shutdown, session_status}, %{state | status: session_status}}
  end

  def handle_info(:session_timeout, state) do
    if is_port(state.port) do
      Port.close(state.port)
    end

    {:stop, {:shutdown, :timed_out}, %{state | status: :timed_out}}
  end

  @impl true
  def terminate(reason, state) do
    if state.timeout_ref, do: Process.cancel_timer(state.timeout_ref)
    File.rm(state.config_path)
    :ok = SessionRegistry.invalidate(state.session_token)
    :ok = Workspace.cleanup(state.workspace_root)

    output =
      state.output_buffer
      |> IO.iodata_to_binary()
      |> String.trim()

    session_status =
      case reason do
        {:shutdown, status} -> status
        _ -> state.status || :failed
      end

    send(state.owner_pid, {:session_ended, self(), session_status, output})
    :ok
  end

  defp build_args(prompt, kind, config_path) do
    profile = ModelRegistry.resolve_agent_profile(kind)

    [
      "-p",
      prompt,
      "--model",
      profile.model_id,
      "--mcp-config",
      config_path,
      "--allowedTools",
      allowed_tools(kind, profile.runtime)
    ]
  end

  defp build_launch_command(claude_path, args, workspace_root) do
    case System.find_executable("env") do
      nil ->
        {claude_path, args}

      env_path ->
        {
          env_path,
          ["-i"] ++
            Enum.map(runtime_env(workspace_root), fn {key, value} -> "#{key}=#{value}" end) ++
            [claude_path | args]
        }
    end
  end

  defp write_mcp_config(session_token) do
    endpoint_base =
      Application.get_env(:forgelet, :mcp_public_base_url, default_base_url())

    mcp_config =
      Jason.encode!(%{
        "mcpServers" => %{
          "forgelet" => %{
            "type" => "url",
            "url" => "#{endpoint_base}/mcp/#{session_token}"
          }
        }
      })

    path = Path.join(System.tmp_dir!(), "forgelet-mcp-#{session_token}.json")
    File.write!(path, mcp_config)
    path
  end

  defp allowed_tools(kind, runtime_name) do
    native_tools = ModelRegistry.runtime_tools(runtime_name, kind)

    mcp_tools =
      ToolRegistry.list_for_kind(kind)
      |> Enum.map(&"mcp__forgelet__#{&1["name"]}")

    Enum.join(native_tools ++ mcp_tools, ",")
  end

  defp timeout_for(kind) do
    Application.get_env(:forgelet, :agent_budgets, %{})
    |> Map.get(kind, %{})
    |> Map.get(:timeout_ms, 600_000)
  end

  defp runtime_env(workspace_root) do
    base_env = [
      {"HOME", workspace_root},
      {"PATH", System.get_env("PATH", "/usr/bin:/bin")},
      {"LANG", System.get_env("LANG", "C.UTF-8")}
    ]

    case CredentialStore.runtime_env(@runtime_name, base_env) do
      {:ok, env} -> env
      {:error, reason} -> raise "missing Claude runtime credentials: #{inspect(reason)}"
    end
  end

  defp default_base_url do
    endpoint = Application.get_env(:forgelet, ForgeletWeb.Endpoint, [])
    url = Keyword.get(endpoint, :url, [])
    host = Keyword.get(url, :host, "localhost")
    http = Keyword.get(endpoint, :http, [])
    port = Keyword.get(http, :port, 4000)
    "http://#{host}:#{port}"
  end
end
