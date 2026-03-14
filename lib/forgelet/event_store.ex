defmodule Forgelet.EventStore do
  @moduledoc """
  Append-only event store backed by ETS (reads) and Postgres (durability).
  Writes are serialized through a GenServer; reads go directly to ETS.
  """

  use GenServer

  alias Forgelet.{Event, EventRecord, Repo, Schema}

  @default_table :forgelet_events

  # Client API

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    table = Keyword.get(opts, :table, @default_table)
    GenServer.start_link(__MODULE__, %{table: table}, name: name)
  end

  def append(event, name \\ __MODULE__) do
    GenServer.call(name, {:append, event})
  end

  def get(id, table \\ @default_table) do
    case :ets.lookup(table, id) do
      [{^id, event}] -> {:ok, event}
      [] -> :error
    end
  end

  def get_by_ref(ref, table \\ @default_table) when is_binary(ref) do
    case Base.decode16(ref, case: :mixed) do
      {:ok, id} ->
        case get(id, table) do
          {:ok, event} -> {:ok, event}
          :error -> {:error, :not_found}
        end

      :error ->
        {:error, :invalid_ref}
    end
  end

  def by_kind(kind, table \\ @default_table) do
    :ets.foldl(
      fn {_id, event}, acc ->
        if event.kind == kind, do: [event | acc], else: acc
      end,
      [],
      table
    )
    |> Enum.sort_by(& &1.timestamp)
  end

  def by_author(author, table \\ @default_table) do
    :ets.foldl(
      fn {_id, event}, acc ->
        if event.author == author, do: [event | acc], else: acc
      end,
      [],
      table
    )
    |> Enum.sort_by(& &1.timestamp)
  end

  def by_scope(scope, table \\ @default_table) do
    :ets.foldl(
      fn {_id, event}, acc ->
        if event.scope == scope, do: [event | acc], else: acc
      end,
      [],
      table
    )
    |> Enum.sort_by(& &1.timestamp)
  end

  def stream(table \\ @default_table) do
    :ets.foldl(fn {_id, event}, acc -> [event | acc] end, [], table)
    |> Enum.sort_by(& &1.timestamp)
  end

  def count(table \\ @default_table) do
    :ets.info(table, :size)
  end

  # Server

  @impl true
  def init(%{table: table}) do
    ets = :ets.new(table, [:set, :public, :named_table, read_concurrency: true])
    load_from_postgres(ets)
    {:ok, %{table: ets}}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def handle_call({:append, event}, _from, state) do
    case validate_and_store(event, state.table) do
      {:ok, event} -> {:reply, {:ok, event}, state}
      {:error, _} = error -> {:reply, error, state}
    end
  end

  defp validate_and_store(event, table) do
    with {:ok, event} <- Event.verify(event),
         :ok <- Schema.validate(event),
         :not_found <- check_duplicate(event.id, table),
         true <- :ets.insert(table, {event.id, event}),
         :ok <- persist_to_postgres(event) do
      broadcast(event)
      {:ok, event}
    else
      {:duplicate, _} ->
        {:error, :duplicate}

      {:error, _} = error ->
        error

      # Postgres failure after ETS insert — rollback ETS
      {:postgres_error, reason} ->
        :ets.delete(table, event.id)
        {:error, reason}
    end
  end

  defp check_duplicate(id, table) do
    case :ets.lookup(table, id) do
      [{^id, _}] -> {:duplicate, id}
      [] -> :not_found
    end
  end

  defp persist_to_postgres(event) do
    record = EventRecord.to_record(event)
    now = DateTime.utc_now()
    callers = Process.get(:"$callers", [])

    fields =
      record
      |> Map.from_struct()
      |> Map.delete(:__meta__)
      |> Map.put(:inserted_at, now)
      |> Map.put(:updated_at, now)

    opts =
      case callers do
        [caller | _] -> [on_conflict: :nothing, caller: caller]
        [] -> [on_conflict: :nothing]
      end

    Repo.insert_all("events", [fields], opts)
    :ok
  rescue
    e ->
      require Logger
      Logger.error("EventStore: Postgres write failed: #{inspect(e)}")
      {:postgres_error, e}
  end

  defp broadcast(event) do
    Phoenix.PubSub.broadcast(Forgelet.PubSub, "events", {:event, event})
    Phoenix.PubSub.broadcast(Forgelet.PubSub, "events:kind:#{event.kind}", {:event, event})

    Phoenix.PubSub.broadcast(
      Forgelet.PubSub,
      "events:author:#{Base.encode16(event.author, case: :lower)}",
      {:event, event}
    )

    if event.scope do
      {type, id} = event.scope

      Phoenix.PubSub.broadcast(
        Forgelet.PubSub,
        "events:scope:#{type}:#{Base.encode16(id, case: :lower)}",
        {:event, event}
      )
    end
  end

  @max_bootstrap_events 10_000

  # Loads up to @max_bootstrap_events from Postgres into ETS on startup.
  # Events beyond this limit are not loaded — they remain in Postgres
  # and can be queried directly via EventRecord.
  defp load_from_postgres(table) do
    import Ecto.Query

    Repo.all(from(e in EventRecord, order_by: [asc: e.timestamp], limit: @max_bootstrap_events))
    |> Enum.each(fn record ->
      event = EventRecord.from_record(record)
      :ets.insert(table, {event.id, event})
    end)
  rescue
    e ->
      require Logger
      Logger.error("EventStore: could not load from Postgres: #{inspect(e)}")
  end
end
