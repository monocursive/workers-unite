defmodule WorkersUniteWeb.Settings.PasskeysLive do
  use WorkersUniteWeb, :live_view

  alias WorkersUnite.Accounts
  alias WorkersUniteWeb.Layouts

  @impl true
  def mount(_params, _session, socket) do
    credentials = Accounts.list_webauthn_credentials(socket.assigns.current_scope)

    {:ok,
     assign(socket,
       page_title: "Passkeys",
       credentials: credentials,
       renaming: nil,
       rename_form: nil
     )}
  end

  @impl true
  def handle_event("start_rename", %{"id" => id}, socket) do
    credential = Accounts.get_webauthn_credential!(socket.assigns.current_scope, id)
    form = to_form(%{"friendly_name" => credential.friendly_name}, as: "credential")
    {:noreply, assign(socket, renaming: id, rename_form: form)}
  end

  @impl true
  def handle_event("cancel_rename", _params, socket) do
    {:noreply, assign(socket, renaming: nil, rename_form: nil)}
  end

  @impl true
  def handle_event("save_rename", %{"credential" => %{"friendly_name" => name}}, socket) do
    case Accounts.rename_webauthn_credential(
           socket.assigns.current_scope,
           socket.assigns.renaming,
           name
         ) do
      {:ok, _credential} ->
        credentials = Accounts.list_webauthn_credentials(socket.assigns.current_scope)
        {:noreply, assign(socket, credentials: credentials, renaming: nil, rename_form: nil)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to rename passkey.")}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    case Accounts.delete_webauthn_credential(socket.assigns.current_scope, id) do
      {:ok, _} ->
        credentials = Accounts.list_webauthn_credentials(socket.assigns.current_scope)

        {:noreply,
         socket
         |> put_flash(:info, "Passkey deleted.")
         |> assign(credentials: credentials)}

      {:error, :last_auth_factor} ->
        {:noreply,
         put_flash(socket, :error, "Cannot delete your only passkey when no password is set.")}
    end
  end

  @impl true
  def handle_event("registered", _params, socket) do
    credentials = Accounts.list_webauthn_credentials(socket.assigns.current_scope)

    {:noreply,
     assign(socket, credentials: credentials) |> put_flash(:info, "Passkey registered.")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-2xl space-y-6">
        <.header>
          Passkeys
          <:subtitle>Manage your passkeys for passwordless authentication.</:subtitle>
        </.header>

        <div class="card bg-base-200 shadow-lg p-6">
          <div class="flex items-center justify-between mb-4">
            <h3 class="font-semibold text-lg">Registered Passkeys</h3>
            <div class="flex items-center gap-2">
              <input
                type="text"
                id="passkey-name-input"
                class="input input-sm input-bordered w-40"
                placeholder="Passkey name"
                maxlength="100"
              />
              <button
                id="register-passkey-btn"
                class="btn btn-primary btn-sm"
                phx-hook="PasskeyRegistration"
                data-label="Add passkey"
              >
                Add passkey
              </button>
            </div>
          </div>

          <div :if={@credentials == []} class="text-base-content/60 text-sm py-4 text-center">
            No passkeys registered yet. Add one to enable passwordless login.
          </div>

          <div :if={@credentials != []} class="divide-y divide-base-300">
            <div :for={credential <- @credentials} class="py-3 flex items-center justify-between">
              <div class="flex-1">
                <%= if @renaming == credential.id do %>
                  <.form
                    for={@rename_form}
                    phx-submit="save_rename"
                    class="flex items-center gap-2"
                  >
                    <input
                      type="text"
                      name="credential[friendly_name]"
                      value={@rename_form[:friendly_name].value}
                      class="input input-sm input-bordered"
                      phx-mounted={JS.focus()}
                    />
                    <button type="submit" class="btn btn-ghost btn-xs">Save</button>
                    <button type="button" class="btn btn-ghost btn-xs" phx-click="cancel_rename">
                      Cancel
                    </button>
                  </.form>
                <% else %>
                  <span class="font-medium">{credential.friendly_name || "Unnamed passkey"}</span>
                  <span :if={credential.last_used_at} class="text-xs text-base-content/50 ml-2">
                    Last used: {Calendar.strftime(credential.last_used_at, "%Y-%m-%d %H:%M")}
                  </span>
                  <span class="text-xs text-base-content/50 ml-2">
                    Added: {Calendar.strftime(credential.inserted_at, "%Y-%m-%d")}
                  </span>
                <% end %>
              </div>
              <div :if={@renaming != credential.id} class="flex items-center gap-1">
                <button
                  class="btn btn-ghost btn-xs"
                  phx-click="start_rename"
                  phx-value-id={credential.id}
                >
                  Rename
                </button>
                <button
                  class="btn btn-ghost btn-xs text-error"
                  phx-click="delete"
                  phx-value-id={credential.id}
                  data-confirm="Are you sure you want to delete this passkey?"
                >
                  Delete
                </button>
              </div>
            </div>
          </div>
        </div>

        <.link navigate={~p"/users/settings"} class="btn btn-ghost btn-sm">
          &larr; Back to settings
        </.link>
      </div>
    </Layouts.app>
    """
  end
end
