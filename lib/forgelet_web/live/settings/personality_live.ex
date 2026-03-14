defmodule ForgeletWeb.Settings.PersonalityLive do
  use ForgeletWeb, :live_view

  @moduledoc """
  Allows the admin to edit the master plan personality -- free-form directives
  injected into orchestrator agent system prompts to shape coordination behavior.
  """

  alias Forgelet.Settings

  @impl true
  def mount(_params, _session, socket) do
    settings = Settings.get()
    personality = settings.master_plan_personality || ""

    {:ok,
     assign(socket,
       page_title: "Orchestrator Personality",
       form: to_form(%{"personality" => personality}, as: "settings")
     )}
  end

  @impl true
  def handle_event("save", %{"settings" => params}, socket) do
    user_id = socket.assigns.current_scope.user.id
    personality = params["personality"] || ""

    case Settings.update(%{master_plan_personality: personality}, user_id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Personality saved.")
         |> assign(form: to_form(%{"personality" => personality}, as: "settings"))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to save.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="space-y-6">
        <div class="flex items-center gap-4">
          <a href={~p"/settings"} class="btn btn-ghost btn-sm">Back</a>
          <h1 class="text-2xl font-bold">Orchestrator Personality</h1>
        </div>

        <div class="card bg-base-200 p-6 space-y-4">
          <p class="text-sm opacity-70">
            These directives are injected into orchestrator agent system prompts.
            Use them to shape how agents coordinate, prioritize, and make decisions.
          </p>
          <form phx-submit="save" class="space-y-4">
            <div class="form-control">
              <textarea
                name="settings[personality]"
                class="textarea textarea-bordered w-full h-48"
                placeholder="e.g., Prioritize test coverage. Prefer small, focused PRs."
              >{@form["personality"].value}</textarea>
            </div>
            <button type="submit" class="btn btn-primary">Save</button>
          </form>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
