defmodule ForgeletWeb.Settings.CredentialsLive do
  use ForgeletWeb, :live_view

  @moduledoc """
  Manages encrypted API credentials for AI runtime providers. Supports creating,
  updating, and deleting credentials with live reload of the credential store.
  """

  alias Forgelet.Credentials

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "API Credentials",
       editing: nil,
       form: to_form(%{"provider" => "", "key_name" => "", "value" => ""}, as: "credential")
     )
     |> load_providers()}
  end

  @impl true
  def handle_event("save_credential", %{"credential" => params}, socket) do
    user_id = socket.assigns.current_scope.user.id

    case Credentials.upsert(params["provider"], params["key_name"], params["value"], user_id) do
      {:ok, _} ->
        try do
          Forgelet.CredentialStore.reload()
        catch
          _, _ -> :ok
        end

        {:noreply,
         socket
         |> put_flash(:info, "Credential saved.")
         |> assign(editing: nil)
         |> load_providers()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to save credential.")}
    end
  end

  def handle_event("delete_credential", %{"id" => id}, socket) do
    case Credentials.delete(id) do
      {:ok, _} ->
        try do
          Forgelet.CredentialStore.reload()
        catch
          _, _ -> :ok
        end

        {:noreply,
         socket
         |> put_flash(:info, "Credential deleted.")
         |> load_providers()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete credential.")}
    end
  end

  def handle_event("edit", %{"provider" => provider, "key" => key}, socket) do
    {:noreply,
     assign(socket,
       editing: {provider, key},
       form:
         to_form(%{"provider" => provider, "key_name" => key, "value" => ""}, as: "credential")
     )}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, editing: nil)}
  end

  defp load_providers(socket) do
    credentials = Credentials.list()
    runtime_registry = Application.get_env(:forgelet, :runtime_registry, %{})

    providers =
      Enum.map(runtime_registry, fn {name, config} ->
        cred_keys = Map.keys(config[:credentials] || %{})
        stored = Enum.filter(credentials, &(&1.provider == to_string(name)))
        stored_keys = Enum.map(stored, & &1.key_name)

        status =
          if cred_keys == [] do
            :no_keys
          else
            missing = Enum.reject(cred_keys, &(&1 in stored_keys))
            if missing == [], do: :complete, else: :partial
          end

        %{name: name, keys: cred_keys, stored: stored, status: status}
      end)

    assign(socket, credentials: credentials, providers: providers)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="space-y-6">
        <div class="flex items-center gap-4">
          <a href={~p"/settings"} class="btn btn-ghost btn-sm">Back</a>
          <h1 class="text-2xl font-bold">API Credentials</h1>
        </div>

        <div :for={provider <- @providers} class="card bg-base-200 p-4 space-y-3">
          <div class="flex items-center gap-3">
            <h2 class="font-semibold">{provider.name}</h2>
            <span class={"badge badge-sm #{status_badge(provider.status)}"}>
              {provider.status}
            </span>
          </div>

          <div :for={key <- provider.keys} class="flex items-center gap-3 text-sm">
            <span class="font-mono flex-1">{key}</span>
            <% stored = Enum.find(provider.stored, &(&1.key_name == key)) %>
            <%= if stored do %>
              <span class="text-success text-xs">configured</span>
              <button
                phx-click="edit"
                phx-value-provider={provider.name}
                phx-value-key={key}
                class="btn btn-ghost btn-xs"
              >
                Update
              </button>
              <button
                phx-click="delete_credential"
                phx-value-id={stored.id}
                data-confirm="Are you sure?"
                class="btn btn-ghost btn-xs text-error"
              >
                Delete
              </button>
            <% else %>
              <span class="text-warning text-xs">not set</span>
              <button
                phx-click="edit"
                phx-value-provider={provider.name}
                phx-value-key={key}
                class="btn btn-ghost btn-xs"
              >
                Set
              </button>
            <% end %>
          </div>

          <%= if @editing && elem(@editing, 0) == to_string(provider.name) do %>
            <form phx-submit="save_credential" class="flex items-end gap-2 mt-2">
              <input type="hidden" name="credential[provider]" value={elem(@editing, 0)} />
              <input type="hidden" name="credential[key_name]" value={elem(@editing, 1)} />
              <div class="form-control flex-1">
                <label class="label text-xs">{elem(@editing, 1)}</label>
                <input
                  type="password"
                  name="credential[value]"
                  required
                  class="input input-bordered input-sm w-full"
                  placeholder="Enter value"
                />
              </div>
              <button type="submit" class="btn btn-primary btn-sm">Save</button>
              <button type="button" phx-click="cancel_edit" class="btn btn-ghost btn-sm">
                Cancel
              </button>
            </form>
          <% end %>

          <p :if={provider.keys == []} class="text-xs opacity-50">
            No credentials configured for this provider.
          </p>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp status_badge(:complete), do: "badge-success"
  defp status_badge(:partial), do: "badge-warning"
  defp status_badge(:no_keys), do: "badge-ghost"
end
