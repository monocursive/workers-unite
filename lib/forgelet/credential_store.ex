defmodule Forgelet.CredentialStore do
  @moduledoc """
  Private credential broker for runtime adapters.

  Secrets are loaded from configured sources into a private ETS table owned by
  this process. They are never exposed through application state, events, or
  prompts. Runtime adapters resolve only the environment variables they need
  immediately before launching an external process.

  On init, DB-stored credentials (via `Forgelet.Credentials`) take precedence
  over env vars when both exist. Call `reload/0` to re-read from DB.
  """

  use GenServer
  require Logger

  @table :forgelet_credentials

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    registry = Keyword.get(opts, :runtime_registry, runtime_registry())

    case name do
      nil -> GenServer.start_link(__MODULE__, %{runtime_registry: registry})
      _ -> GenServer.start_link(__MODULE__, %{runtime_registry: registry}, name: name)
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
  Reload credentials from DB, merging over env-var defaults.
  """
  def reload(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.call(name, :reload)
  end

  @impl true
  def init(%{runtime_registry: registry}) do
    table = :ets.new(@table, [:set, :private])
    load_all(table, registry)
    {:ok, %{table: table, runtime_registry: registry}}
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

  def handle_call(:reload, _from, state) do
    load_all(state.table, state.runtime_registry)
    {:reply, :ok, state}
  end

  defp load_all(table, registry) do
    Enum.each(registry, fn {runtime_name, runtime_config} ->
      env_credentials =
        runtime_config
        |> Map.get(:credentials, %{})
        |> resolve_credentials()

      db_credentials = load_db_credentials(runtime_name)

      merged = Map.merge(env_credentials, db_credentials)
      true = :ets.insert(table, {runtime_name, merged})
    end)
  end

  defp load_db_credentials(runtime_name) do
    if repo_available?() do
      try do
        Forgelet.Credentials.all_decrypted_for_provider(runtime_name)
      rescue
        e ->
          Logger.warning("Failed to load DB credentials for #{runtime_name}: #{inspect(e)}")
          %{}
      catch
        kind, reason ->
          Logger.warning(
            "Failed to load DB credentials for #{runtime_name}: #{inspect(kind)} #{inspect(reason)}"
          )

          %{}
      end
    else
      %{}
    end
  end

  defp repo_available? do
    try do
      Forgelet.Repo.__adapter__()
      Process.whereis(Forgelet.Repo) != nil
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
    Application.get_env(:forgelet, :runtime_registry, %{})
  end
end
