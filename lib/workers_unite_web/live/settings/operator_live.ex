defmodule WorkersUniteWeb.Settings.OperatorLive do
  use WorkersUniteWeb, :live_view

  @moduledoc """
  Manages operator access tokens for external MCP clients like OpenCode.
  Shows setup instructions and provides token creation/revocation.
  """

  alias Phoenix.LiveView.JS
  alias WorkersUnite.Operator

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    tokens = Operator.list_tokens(user)

    {:ok,
     assign(socket,
       page_title: "Operator Tokens",
       tokens: tokens,
       new_plaintext: nil,
       form: to_form(%{"name" => "", "scopes" => []}, as: "token")
     )}
  end

  @impl true
  def handle_event("create_token", %{"token" => params}, socket) do
    user = socket.assigns.current_scope.user
    name = params["name"] || ""
    scopes = parse_scopes(params)
    expires_at = parse_expires_at(params["expires_in"])

    case Operator.create_token(user, name, scopes, expires_at: expires_at) do
      {:ok, plaintext, _token} ->
        tokens = Operator.list_tokens(user)

        {:noreply,
         socket
         |> assign(
           tokens: tokens,
           new_plaintext: plaintext,
           form: to_form(%{"name" => "", "scopes" => []}, as: "token")
         )
         |> put_flash(:info, "Token created. Copy it now -- it won't be shown again.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create token. Check name and scopes.")}
    end
  end

  def handle_event("dismiss_plaintext", _params, socket) do
    {:noreply, assign(socket, new_plaintext: nil)}
  end

  def handle_event("revoke_token", %{"id" => id}, socket) do
    user = socket.assigns.current_scope.user

    case Operator.revoke_token(id, user) do
      {:ok, _token} ->
        tokens = Operator.list_tokens(user)

        {:noreply,
         socket
         |> assign(tokens: tokens)
         |> put_flash(:info, "Token revoked.")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Token not found.")}

      {:error, :already_revoked} ->
        {:noreply, put_flash(socket, :error, "Token already revoked.")}
    end
  end

  defp parse_scopes(params) do
    scopes = []
    scopes = if params["scope_observe"] == "true", do: ["observe" | scopes], else: scopes
    scopes = if params["scope_control"] == "true", do: ["control" | scopes], else: scopes
    Enum.reverse(scopes)
  end

  defp parse_expires_at("30"), do: DateTime.add(DateTime.utc_now(), 30, :day)
  defp parse_expires_at("90"), do: DateTime.add(DateTime.utc_now(), 90, :day)
  defp parse_expires_at("365"), do: DateTime.add(DateTime.utc_now(), 365, :day)
  defp parse_expires_at(_), do: nil

  defp base_url do
    WorkersUniteWeb.Endpoint.url()
  end

  defp mcp_config_snippet do
    url = "#{base_url()}/operator/mcp"

    Jason.encode!(
      %{
        "mcpServers" => %{
          "workers-unite" => %{
            "type" => "http",
            "url" => url,
            "headers" => %{"Authorization" => "Bearer {YOUR_TOKEN}"}
          }
        }
      },
      pretty: true
    )
  end

  defp mcp_config_snippet_with_token(token) do
    url = "#{base_url()}/operator/mcp"

    Jason.encode!(
      %{
        "mcpServers" => %{
          "workers-unite" => %{
            "type" => "http",
            "url" => url,
            "headers" => %{"Authorization" => "Bearer #{token}"}
          }
        }
      },
      pretty: true
    )
  end

  defp token_status(token) do
    cond do
      token.revoked_at != nil ->
        :revoked

      token.expires_at != nil and DateTime.compare(token.expires_at, DateTime.utc_now()) == :lt ->
        :expired

      true ->
        :active
    end
  end

  defp status_badge(:active), do: "badge-success"
  defp status_badge(:revoked), do: "badge-error"
  defp status_badge(:expired), do: "badge-warning"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="space-y-8">
        <div class="flex items-center gap-4">
          <a href={~p"/settings"} class="btn btn-ghost btn-sm">Back</a>
          <h1 class="text-2xl font-bold">Operator Tokens</h1>
        </div>

        <%!-- OpenCode Setup Instructions --%>
        <div class="card bg-base-200 p-6 space-y-4">
          <h2 class="font-semibold text-lg">Connect OpenCode</h2>
          <p class="text-sm opacity-70">
            Use an operator token to connect external MCP clients (like OpenCode) to this WorkersUnite instance.
          </p>
          <ol class="list-decimal list-inside text-sm space-y-1 opacity-80">
            <li>Generate a token below</li>
            <li>Add the MCP server to your OpenCode configuration</li>
            <li>Start using WorkersUnite tools from your editor</li>
          </ol>
          <div class="text-sm">
            <p class="font-medium mb-1">MCP endpoint:</p>
            <code class="block bg-base-300 rounded px-3 py-2 text-xs font-mono break-all">
              {base_url()}/operator/mcp
            </code>
            <p class="text-xs opacity-60 mt-1">
              Token is sent via <code>Authorization: Bearer &lt;token&gt;</code> header
            </p>
          </div>
          <div class="text-sm">
            <p class="font-medium mb-1">OpenCode MCP config snippet:</p>
            <pre class="bg-base-300 rounded px-3 py-2 text-xs font-mono overflow-x-auto">{mcp_config_snippet()}</pre>
          </div>
        </div>

        <%!-- New token plaintext display --%>
        <div :if={@new_plaintext} class="card bg-success/10 border border-success p-4 space-y-2">
          <p class="font-semibold text-sm">
            Your new token (copy it now -- it won't be shown again):
          </p>
          <div class="flex items-center gap-2">
            <code class="block flex-1 bg-base-300 rounded px-3 py-2 text-xs font-mono break-all select-all">
              {@new_plaintext}
            </code>
            <button
              phx-click={JS.dispatch("phx:clipboard", detail: %{text: @new_plaintext})}
              class="btn btn-ghost btn-xs"
              title="Copy token"
            >
              Copy
            </button>
          </div>
          <details class="text-sm">
            <summary class="cursor-pointer text-xs opacity-60">MCP config snippet</summary>
            <div class="flex items-center gap-2 mt-1">
              <pre class="flex-1 bg-base-300 rounded px-3 py-2 text-xs font-mono overflow-x-auto">{mcp_config_snippet_with_token(@new_plaintext)}</pre>
              <button
                phx-click={
                  JS.dispatch("phx:clipboard",
                    detail: %{text: mcp_config_snippet_with_token(@new_plaintext)}
                  )
                }
                class="btn btn-ghost btn-xs"
                title="Copy config"
              >
                Copy
              </button>
            </div>
          </details>
          <button phx-click="dismiss_plaintext" class="btn btn-ghost btn-xs">Dismiss</button>
        </div>

        <%!-- Create Token Form --%>
        <div class="card bg-base-200 p-6 space-y-4">
          <h2 class="font-semibold text-lg">Create Token</h2>
          <form phx-submit="create_token" class="space-y-4">
            <div class="form-control">
              <label class="label text-sm">Token name</label>
              <input
                type="text"
                name="token[name]"
                required
                class="input input-bordered input-sm w-full max-w-xs"
                placeholder="e.g. opencode-laptop"
              />
            </div>
            <div class="form-control">
              <label class="label text-sm">Scopes</label>
              <div class="space-y-2">
                <label class="flex items-start gap-2 cursor-pointer">
                  <input type="hidden" name="token[scope_observe]" value="false" />
                  <input
                    type="checkbox"
                    name="token[scope_observe]"
                    value="true"
                    checked
                    class="checkbox checkbox-sm mt-0.5"
                  />
                  <div>
                    <span class="text-sm font-medium">observe</span>
                    <p class="text-xs opacity-60">
                      Read-only access to agents, repos, events, and sessions
                    </p>
                  </div>
                </label>
                <label class="flex items-start gap-2 cursor-pointer">
                  <input type="hidden" name="token[scope_control]" value="false" />
                  <input
                    type="checkbox"
                    name="token[scope_control]"
                    value="true"
                    class="checkbox checkbox-sm mt-0.5"
                  />
                  <div>
                    <span class="text-sm font-medium">control</span>
                    <p class="text-xs opacity-60">
                      Publish intents, cast votes, dispatch work, cancel sessions
                    </p>
                  </div>
                </label>
              </div>
            </div>
            <div class="form-control">
              <label class="label text-sm">Expires</label>
              <select
                name="token[expires_in]"
                class="select select-bordered select-sm w-full max-w-xs"
              >
                <option value="">Never</option>
                <option value="30">30 days</option>
                <option value="90">90 days</option>
                <option value="365">1 year</option>
              </select>
            </div>
            <button type="submit" class="btn btn-primary btn-sm">Create Token</button>
          </form>
        </div>

        <%!-- Token List --%>
        <div class="card bg-base-200 p-6 space-y-4">
          <h2 class="font-semibold text-lg">Existing Tokens</h2>
          <div :if={@tokens == []} class="text-sm opacity-60">No tokens yet.</div>
          <div class="overflow-x-auto">
            <table :if={@tokens != []} class="table table-sm">
              <thead>
                <tr>
                  <th>Name</th>
                  <th>Prefix</th>
                  <th>Scopes</th>
                  <th>Last Used</th>
                  <th>Status</th>
                  <th>Created</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                <tr :for={token <- @tokens}>
                  <td class="font-medium">{token.name}</td>
                  <td class="font-mono text-xs">{token.token_prefix}...</td>
                  <td>
                    <span :for={scope <- token.scopes} class="badge badge-ghost badge-xs mr-1">
                      {scope}
                    </span>
                  </td>
                  <td class="text-xs opacity-60">
                    {if token.last_used_at,
                      do: Calendar.strftime(token.last_used_at, "%Y-%m-%d %H:%M"),
                      else: "Never"}
                  </td>
                  <td>
                    <span class={"badge badge-xs #{status_badge(token_status(token))}"}>
                      {token_status(token)}
                    </span>
                  </td>
                  <td class="text-xs opacity-60">
                    {Calendar.strftime(token.inserted_at, "%Y-%m-%d %H:%M")}
                  </td>
                  <td>
                    <button
                      :if={token_status(token) == :active}
                      phx-click="revoke_token"
                      phx-value-id={token.id}
                      data-confirm="Revoke this token? It cannot be undone."
                      class="btn btn-ghost btn-xs text-error"
                    >
                      Revoke
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
