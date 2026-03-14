defmodule WorkersUnite.CredentialStore do
  @moduledoc """
  Private credential broker for runtime adapters.

  Secrets are loaded from configured sources into a private ETS table owned by
  this process. They are never exposed through application state, events, or
  prompts. Runtime adapters resolve only the environment variables they need
  immediately before launching an external process.

  On init, DB-stored credentials (via `WorkersUnite.Credentials`) take precedence
  over env vars when both exist. Call `reload/0` to re-read from DB.

  Supports both runtime-based credential lookup (legacy) and provider-based
  credential lookup (for OpenCode runtime with pluggable model providers).
  """

  use GenServer
  require Logger

  @table :workers_unite_credentials
  @provider_table :workers_unite_provider_credentials

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    registry = Keyword.get(opts, :runtime_registry, runtime_registry())
    provider_registry = Keyword.get(opts, :provider_registry, provider_registry())
    load_db_credentials? = Keyword.get(opts, :load_db_credentials?, true)

    case name do
      nil ->
        GenServer.start_link(__MODULE__, %{
          runtime_registry: registry,
          provider_registry: provider_registry,
          load_db_credentials?: load_db_credentials?
        })

      _ ->
        GenServer.start_link(
          __MODULE__,
          %{
            runtime_registry: registry,
            provider_registry: provider_registry,
            load_db_credentials?: load_db_credentials?
          },
          name: name
        )
    end
  end

  def runtime_env(runtime_name, base_env \\ [], opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.call(name, {:runtime_env, runtime_name, base_env})
  end

  def runtime_metadata(runtime_name, opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.call(name, {:runtime_metadata, runtime_name})
  end

  @doc """
  Returns environment variables for a specific provider.
  Used by OpenCode runtime to resolve credentials based on the selected model's provider.
  """
  def provider_env(provider, base_env \\ [], opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.call(name, {:provider_env, provider, base_env})
  end

  @doc """
  Checks if a provider has all required credentials configured.
  """
  def provider_configured?(provider, opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.call(name, {:provider_configured, provider})
  end

  @doc """
  Reload credentials from DB, merging over env-var defaults.
  """
  def reload(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    caller = Keyword.get(opts, :caller)
    GenServer.call(name, {:reload, caller})
  end

  @impl true
  def init(%{
        runtime_registry: runtime_registry,
        provider_registry: provider_registry,
        load_db_credentials?: load_db_credentials?
      }) do
    table = :ets.new(@table, [:set, :private])
    provider_table = :ets.new(@provider_table, [:set, :private])
    load_all(table, runtime_registry, load_db_credentials?: load_db_credentials?)
    load_providers(provider_table, provider_registry, load_db_credentials?: load_db_credentials?)

    {:ok,
     %{
       table: table,
       provider_table: provider_table,
       runtime_registry: runtime_registry,
       provider_registry: provider_registry,
       load_db_credentials?: load_db_credentials?
     }}
  end

  @impl true
  def handle_call({:runtime_env, runtime_name, base_env}, _from, state) do
    reply =
      case :ets.lookup(state.table, runtime_name) do
        [{^runtime_name, credentials}] ->
          case Enum.filter(credentials, fn {_key, value} -> match?({:missing, _}, value) end) do
            [] ->
              env =
                base_env ++
                  Enum.map(credentials, fn {key, value} ->
                    {key, unwrap_credential(value)}
                  end)

              {:ok, env}

            missing ->
              {:error,
               {:missing_credentials,
                Enum.map(missing, fn {_key, {:missing, env_var}} -> env_var end)}}
          end

        [] ->
          {:ok, base_env}
      end

    {:reply, reply, state}
  end

  def handle_call({:runtime_metadata, runtime_name}, _from, state) do
    metadata =
      state.runtime_registry
      |> Map.get(runtime_name, %{})
      |> Map.update(:credentials, %{}, fn credentials ->
        Map.new(credentials, fn {env_var, _source} -> {env_var, :configured} end)
      end)

    {:reply, metadata, state}
  end

  def handle_call({:provider_env, provider, base_env}, _from, state) do
    reply =
      if Map.has_key?(state.provider_registry, provider) do
        case :ets.lookup(state.provider_table, provider) do
          [{^provider, credentials}] ->
            case Enum.filter(credentials, fn {_key, value} -> match?({:missing, _}, value) end) do
              [] ->
                env =
                  base_env ++
                    Enum.map(credentials, fn {key, value} ->
                      {key, unwrap_credential(value)}
                    end)

                {:ok, env}

              missing ->
                {:error,
                 {:missing_credentials,
                  Enum.map(missing, fn {_key, {:missing, env_var}} -> env_var end)}}
            end

          [] ->
            {:ok, base_env}
        end
      else
        {:error, {:unknown_provider, provider}}
      end

    {:reply, reply, state}
  end

  def handle_call({:provider_configured, provider}, _from, state) do
    configured =
      case :ets.lookup(state.provider_table, provider) do
        [{^provider, credentials}] ->
          not Enum.any?(credentials, fn {_key, value} -> match?({:missing, _}, value) end)

        [] ->
          false
      end

    {:reply, configured, state}
  end

  def handle_call({:reload, caller}, _from, state) do
    opts = [caller: caller, load_db_credentials?: state.load_db_credentials?]
    load_all(state.table, state.runtime_registry, opts)
    load_providers(state.provider_table, state.provider_registry, opts)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  defp load_all(table, registry, opts) do
    Enum.each(registry, fn {runtime_name, runtime_config} ->
      env_credentials =
        runtime_config
        |> Map.get(:credentials, %{})
        |> resolve_credentials()

      db_credentials = load_db_credentials(runtime_name, opts)

      merged = Map.merge(env_credentials, db_credentials)
      true = :ets.insert(table, {runtime_name, merged})
    end)
  end

  defp load_providers(table, registry, opts) do
    Enum.each(registry, fn {provider, config} ->
      env_credentials =
        config
        |> Map.get(:credentials, %{})
        |> resolve_credentials()

      db_credentials = load_db_credentials(provider, opts)

      merged = Map.merge(env_credentials, db_credentials)
      true = :ets.insert(table, {provider, merged})
    end)
  end

  defp load_db_credentials(provider, opts) do
    if Keyword.get(opts, :load_db_credentials?, true) and repo_available?() do
      try do
        repo_opts =
          case Keyword.get(opts, :caller) do
            nil -> []
            caller -> [caller: caller]
          end

        WorkersUnite.Credentials.all_decrypted_for_provider(provider, repo_opts)
      rescue
        e ->
          Logger.warning("Failed to load DB credentials for #{provider}: #{inspect(e)}")
          %{}
      catch
        kind, reason ->
          Logger.warning(
            "Failed to load DB credentials for #{provider}: #{inspect(kind)} #{inspect(reason)}"
          )

          %{}
      end
    else
      %{}
    end
  end

  defp repo_available? do
    try do
      WorkersUnite.Repo.__adapter__()
      Process.whereis(WorkersUnite.Repo) != nil
    rescue
      _ -> false
    end
  end

  defp resolve_credentials(credentials) do
    Map.new(credentials, fn {env_var, source} ->
      {env_var, resolve_credential(source)}
    end)
  end

  defp resolve_credential({:system, env_var}) do
    case System.get_env(env_var) do
      nil -> {:missing, env_var}
      value -> value
    end
  end

  defp resolve_credential({:literal, value}) when is_binary(value), do: value

  defp unwrap_credential(value) when is_binary(value), do: value

  defp runtime_registry do
    Application.get_env(:workers_unite, :runtime_registry, %{})
  end

  defp provider_registry do
    Application.get_env(:workers_unite, :provider_registry, %{})
  end
end
