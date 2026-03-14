defmodule ForgeletWeb.SettingsLive do
  use ForgeletWeb, :live_view

  @moduledoc """
  Instance settings dashboard providing navigation to credential management
  and orchestrator personality configuration, plus instance metadata.
  """

  alias Forgelet.Settings

  @impl true
  def mount(_params, _session, socket) do
    settings = Settings.get()

    {:ok,
     assign(socket,
       page_title: "Instance Settings",
       settings: settings
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="space-y-6">
        <h1 class="text-2xl font-bold">Instance Settings</h1>

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <a
            href={~p"/settings/credentials"}
            class="card bg-base-200 p-6 hover:bg-base-300 transition-colors space-y-2"
          >
            <h2 class="font-semibold text-lg">API Credentials</h2>
            <p class="text-sm opacity-70">Manage encrypted API keys for runtime providers.</p>
          </a>
          <a
            href={~p"/settings/personality"}
            class="card bg-base-200 p-6 hover:bg-base-300 transition-colors space-y-2"
          >
            <h2 class="font-semibold text-lg">Orchestrator Personality</h2>
            <p class="text-sm opacity-70">Configure directives injected into orchestrator prompts.</p>
          </a>
        </div>

        <div class="card bg-base-200 p-6 space-y-2">
          <h2 class="font-semibold">Instance Info</h2>
          <div class="text-sm">
            <span class="opacity-70">Onboarding completed:</span>
            <span>
              {if @settings.onboarding_completed_at,
                do: Calendar.strftime(@settings.onboarding_completed_at, "%Y-%m-%d %H:%M UTC"),
                else: "Not yet"}
            </span>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
