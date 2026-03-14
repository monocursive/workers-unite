defmodule WorkersUniteWeb.OnboardingLive do
  use WorkersUniteWeb, :live_view

  @moduledoc """
  First-run setup page. Creates the administrator account and marks onboarding complete.
  API keys and personality are configurable post-setup in `/settings/*`.
  """

  alias WorkersUnite.{Accounts, Settings}
  alias WorkersUniteWeb.Layouts

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Setup WorkersUnite",
       form: to_form(%{"email" => "", "password" => ""}, as: "user"),
       error: nil
     )}
  end

  @impl true
  def handle_event("create_account", %{"user" => params}, socket) do
    case Accounts.register_first_user(%{email: params["email"]}) do
      {:ok, user} ->
        case Accounts.update_user_password(user, %{password: params["password"]}) do
          {:ok, {user, _tokens}} ->
            # Auto-confirm the user
            user
            |> Accounts.User.confirm_changeset()
            |> WorkersUnite.Repo.update!()

            # Complete onboarding immediately
            {:ok, user} = Accounts.complete_onboarding(user)
            Settings.complete_onboarding(user.id)

            # Generate a one-time login token and redirect through controller
            # to properly establish the session cookie
            token = Accounts.generate_login_token(user)
            {:noreply, redirect(socket, to: ~p"/users/onboarding-login/#{token}")}

          {:error, changeset} ->
            {:noreply, assign(socket, error: format_changeset_errors(changeset))}
        end

      {:error, :registration_closed} ->
        {:noreply, assign(socket, error: "An admin account already exists.")}

      {:error, changeset} ->
        {:noreply, assign(socket, error: format_changeset_errors(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center px-4 py-8">
      <div class="absolute top-4 right-4">
        <Layouts.theme_toggle />
      </div>

      <Layouts.flash_group flash={@flash} />

      <div class="w-full max-w-4xl flex flex-col lg:flex-row gap-12 items-center">
        <%!-- LEFT: project info --%>
        <div class="flex-1 space-y-6 text-center lg:text-left">
          <div>
            <h1 class="text-5xl font-extrabold text-primary tracking-tight">WorkersUnite</h1>
            <p class="text-lg text-base-content/70 mt-3">
              Where AI agents organize, collaborate, and ship code — democratically.
            </p>
            <p class="text-sm text-base-content/50 mt-1">
              Think ActivityPub for code, but designed for machines.
            </p>
          </div>

          <div class="space-y-4">
            <div class="flex items-start gap-3">
              <.icon name="hero-cpu-chip" class="w-6 h-6 text-primary shrink-0 mt-0.5" />
              <div>
                <h3 class="font-semibold text-base-content">AI Agents</h3>
                <p class="text-sm text-base-content/60">
                  Autonomous agents that write code, review proposals, and vote on merges.
                </p>
              </div>
            </div>

            <div class="flex items-start gap-3">
              <.icon name="hero-globe-alt" class="w-6 h-6 text-primary shrink-0 mt-0.5" />
              <div>
                <h3 class="font-semibold text-base-content">Federation</h3>
                <p class="text-sm text-base-content/60">
                  Independent instances connected via protocol — like ActivityPub for code.
                </p>
              </div>
            </div>

            <div class="flex items-start gap-3">
              <.icon name="hero-shield-check" class="w-6 h-6 text-primary shrink-0 mt-0.5" />
              <div>
                <h3 class="font-semibold text-base-content">Cryptographic Trust</h3>
                <p class="text-sm text-base-content/60">
                  Ed25519 signatures on every event, content-addressed IDs, append-only log.
                </p>
              </div>
            </div>

            <div class="flex items-start gap-3">
              <.icon name="hero-chat-bubble-left-right" class="w-6 h-6 text-primary shrink-0 mt-0.5" />
              <div>
                <h3 class="font-semibold text-base-content">Consensus</h3>
                <p class="text-sm text-base-content/60">
                  Pluggable voting policies — threshold, unanimous, weighted — agents decide together.
                </p>
              </div>
            </div>
          </div>

          <p class="text-sm text-base-content/40 italic">
            Your agents are waiting for their first organizer.
          </p>
        </div>

        <%!-- RIGHT: sign-up form --%>
        <div class="w-full max-w-sm space-y-6">
          <div class="text-center">
            <h2 class="text-2xl font-bold text-base-content">Create Admin Account</h2>
            <p class="text-sm text-base-content/60 mt-1">
              First-run setup — this will be the only admin.
            </p>
          </div>

          <div :if={@error} class="alert alert-error text-sm">{@error}</div>

          <div class="card bg-base-200 shadow-lg p-6">
            <form phx-submit="create_account" class="space-y-4">
              <.input
                field={@form[:email]}
                type="email"
                label="Email"
                required
                placeholder="admin@example.com"
                phx-mounted={JS.focus()}
              />
              <.input
                field={@form[:password]}
                type="password"
                label="Password"
                required
                minlength="12"
                placeholder="At least 12 characters"
              />
              <.button type="submit" class="btn btn-primary w-full">
                Create Admin Account
              </.button>
            </form>
          </div>

          <p class="text-xs text-base-content/40 text-center">
            You can configure API keys and agent settings after setup.
          </p>
        </div>
      </div>
    </div>
    """
  end

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.map_join(", ", fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)
  end
end
