defmodule WorkersUniteWeb.Settings.ModelLive do
  use WorkersUniteWeb, :live_view

  @moduledoc """
  Manages the global default model selection for agent runtimes.
  """

  alias WorkersUnite.Settings

  @impl true
  def mount(_params, _session, socket) do
    settings = Settings.get()
    catalog = Settings.model_catalog()

    {:ok,
     socket
     |> assign(
       page_title: "Model Settings",
       settings: settings,
       catalog: catalog,
       selected_model: settings.default_agent_model
     )
     |> load_provider_status()}
  end

  @impl true
  def handle_event("select_model", %{"model_key" => model_key}, socket) do
    user_id = socket.assigns.current_scope.user.id
    entry = Enum.find(socket.assigns.catalog, fn e -> e.key == model_key end)

    cond do
      entry == nil ->
        {:noreply, put_flash(socket, :error, "Invalid model selection.")}

      not Settings.provider_configured?(entry.provider) ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Cannot select #{entry.label}: #{format_provider(entry.provider)} API key not configured."
         )}

      true ->
        case Settings.set_default_agent_model(model_key, user_id) do
          {:ok, settings} ->
            {:noreply,
             socket
             |> put_flash(:info, "Default model updated to #{entry.label}")
             |> assign(settings: settings, selected_model: model_key)
             |> load_provider_status()}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to update model.")}
        end
    end
  end

  defp load_provider_status(socket) do
    provider_status =
      socket.assigns.catalog
      |> Enum.map(fn entry ->
        {entry.key, Settings.provider_configured?(entry.provider)}
      end)
      |> Map.new()

    assign(socket, provider_status: provider_status)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="model-settings" class="space-y-6">
        <div class="flex items-center gap-4">
          <.link navigate={~p"/settings"} class="btn btn-ghost btn-sm">Back</.link>
          <h1 class="text-2xl font-bold">Model Settings</h1>
        </div>

        <p class="text-sm opacity-70">
          Select the default model for all agent kinds. The selected model determines which provider's API key is required.
        </p>

        <div class="card bg-base-200 p-4">
          <h2 class="font-semibold mb-4">Available Models</h2>

          <div class="space-y-2">
            <div
              :for={entry <- @catalog}
              class="flex items-center gap-3 p-3 rounded-lg hover:bg-base-300 transition-colors"
            >
              <input
                id={"model-#{entry.key}"}
                type="radio"
                name="model_selection"
                value={entry.key}
                checked={@selected_model == entry.key}
                phx-value-model_key={entry.key}
                phx-click="select_model"
                class="radio radio-primary"
              />
              <div class="flex-1">
                <div class="font-medium">{entry.label}</div>
                <div class="text-xs opacity-60">
                  Provider: {format_provider(entry.provider)} | Model: {entry.model_id}
                </div>
              </div>
              <div class="flex items-center gap-2">
                <%= if @provider_status[entry.key] do %>
                  <span class="badge badge-success badge-sm">configured</span>
                <% else %>
                  <span class="badge badge-warning badge-sm">key required</span>
                <% end %>
              </div>
            </div>
          </div>

          <div :if={@catalog == []} class="text-sm opacity-50">
            No models configured in the catalog.
          </div>
        </div>

        <div class="card bg-base-200 p-4">
          <h2 class="font-semibold mb-2">Current Selection</h2>
          <p class="text-sm">
            <%= if @selected_model do %>
              <span class="font-mono">{@selected_model}</span>
            <% else %>
              <span class="opacity-60">No model selected (first catalog entry will be used)</span>
            <% end %>
          </p>
        </div>

        <div class="card bg-base-200 p-4">
          <h2 class="font-semibold mb-2">Provider Keys</h2>
          <p class="text-sm opacity-70 mb-3">
            Ensure the required provider API key is configured before selecting a model.
          </p>
          <.link
            id="manage-credentials-link"
            navigate={~p"/settings/credentials"}
            class="btn btn-outline btn-sm"
          >
            Manage Credentials
          </.link>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp format_provider(:anthropic), do: "Anthropic"
  defp format_provider(:openai), do: "OpenAI"
  defp format_provider(:google), do: "Google"
  defp format_provider(:azure), do: "Azure"
  defp format_provider(provider) when is_atom(provider), do: format_provider(to_string(provider))

  defp format_provider(provider) do
    provider
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
end
