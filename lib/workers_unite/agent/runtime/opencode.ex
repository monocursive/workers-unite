defmodule WorkersUnite.Agent.Runtime.OpenCode do
  @moduledoc """
  OpenCode CLI runtime adapter.

  Spawns external OpenCode CLI processes with MCP config injection, enforces
  timeouts, captures output, and cleans up session root and token on exit.
  """

  use GenServer

  @behaviour WorkersUnite.Agent.Runtime

  alias WorkersUnite.{CredentialStore, ModelRegistry}
  alias WorkersUnite.Agent.{SessionRegistry, SystemPrompt, Workspace}
  alias WorkersUniteWeb.MCP.ToolRegistry

  @impl true
  def start_run(owner_pid, agent_id, kind, opts \\ []) do
    owner_user_id = Keyword.get(opts, :owner_user_id)

    with {:ok, workspace_root} <- Workspace.create_session_root(),
         {:ok, token} <- SessionRegistry.create(agent_id, kind, workspace_root, owner_user_id) do
      child_spec =
        {__MODULE__,
         Keyword.merge(opts,
           owner_pid: owner_pid,
           agent_id: agent_id,
           kind: kind,
           workspace_root: workspace_root,
           session_token: token
         )}

      case DynamicSupervisor.start_child(WorkersUnite.SessionSupervisor, child_spec) do
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
    DynamicSupervisor.terminate_child(WorkersUnite.SessionSupervisor, pid)
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
    extra_env = Keyword.get(opts, :env, [])

    with {:ok, model_id, provider} <- resolve_model_from_catalog() do
      config_path = write_mcp_config(session_token)
      prompt = SystemPrompt.build(kind, agent_id, task_context, workspace_root)
      opencode_path = Application.get_env(:workers_unite, :opencode_cli_path, "opencode")

      args = build_args(prompt, kind, config_path, model_id)

      {launch_path, launch_args} =
        build_launch_command(opencode_path, args, workspace_root, provider, extra_env)

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
    else
      {:error, reason} ->
        {:stop, reason}
    end
  rescue
    error ->
      {:stop, error}
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    {:noreply, %{state | output_buffer: [data | state.output_buffer]}}
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

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(reason, state) do
    if state.timeout_ref, do: Process.cancel_timer(state.timeout_ref)
    File.rm(state.config_path)
    :ok = SessionRegistry.invalidate(state.session_token)
    :ok = Workspace.cleanup(state.workspace_root)

    output =
      state.output_buffer
      |> Enum.reverse()
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

  defp resolve_model_from_catalog do
    {model_id, provider} = ModelRegistry.resolve_model_from_catalog()
    {:ok, model_id, provider}
  end

  defp build_args(prompt, kind, config_path, model_id) do
    profile = ModelRegistry.resolve_agent_profile(kind)

    [
      "-p",
      prompt,
      "--model",
      model_id,
      "--mcp-config",
      config_path,
      "--allowedTools",
      allowed_tools(kind, profile.runtime)
    ]
  end

  defp build_launch_command(opencode_path, args, workspace_root, provider, extra_env) do
    case System.find_executable("env") do
      nil ->
        {opencode_path, args}

      env_path ->
        provider_env = provider_env_vars(provider, workspace_root, extra_env)

        {
          env_path,
          ["-i"] ++
            Enum.map(provider_env, fn {key, value} -> "#{key}=#{value}" end) ++
            [opencode_path | args]
        }
    end
  end

  defp provider_env_vars(provider, workspace_root, extra_env) do
    base_env = [
      {"HOME", workspace_root},
      {"PATH", System.get_env("PATH", "/usr/bin:/bin")},
      {"LANG", System.get_env("LANG", "C.UTF-8")}
    ]

    case CredentialStore.provider_env(provider, base_env ++ extra_env) do
      {:ok, env} -> env
      {:error, reason} -> raise "missing provider credentials for #{provider}: #{inspect(reason)}"
    end
  end

  defp write_mcp_config(session_token) do
    endpoint_base =
      Application.get_env(:workers_unite, :mcp_public_base_url, default_base_url())

    mcp_config =
      Jason.encode!(%{
        "mcpServers" => %{
          "workers_unite" => %{
            "type" => "url",
            "url" => "#{endpoint_base}/mcp/#{session_token}"
          }
        }
      })

    path = Path.join(System.tmp_dir!(), "workers-unite-mcp-#{session_token}.json")
    File.write!(path, mcp_config)
    :ok = :file.change_mode(to_charlist(path), 0o600)
    path
  end

  defp allowed_tools(kind, runtime_name) do
    native_tools = ModelRegistry.runtime_tools(runtime_name, kind)

    mcp_tools =
      ToolRegistry.list_for_kind(kind)
      |> Enum.map(&"mcp__workers_unite__#{&1["name"]}")

    Enum.join(native_tools ++ mcp_tools, ",")
  end

  defp timeout_for(kind) do
    Application.get_env(:workers_unite, :agent_budgets, %{})
    |> Map.get(kind, %{})
    |> Map.get(:timeout_ms, 600_000)
  end

  defp default_base_url do
    endpoint = Application.get_env(:workers_unite, WorkersUniteWeb.Endpoint, [])
    url = Keyword.get(endpoint, :url, [])
    host = Keyword.get(url, :host, "localhost")
    http = Keyword.get(endpoint, :http, [])
    port = Keyword.get(http, :port, 4000)
    "http://#{host}:#{port}"
  end
end
