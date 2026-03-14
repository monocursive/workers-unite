defmodule WorkersUniteWeb.OnboardingLive do
  use WorkersUniteWeb, :live_view

  @moduledoc """
  First-run setup page. Creates the administrator account, then offers an
  optional passkey step before onboarding is marked complete.
  """

  alias WorkersUnite.{Accounts, Settings}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Setup WorkersUnite",
       step: onboarding_step(socket.assigns.current_scope),
       form: account_form(),
       handoff_form: nil,
       error: nil
     )}
  end

  @impl true
  def handle_event("create_account", %{"user" => params}, socket) do
    case Accounts.register_first_user(%{email: params["email"]}) do
      {:ok, user} ->
        case Accounts.update_user_password(user, %{password: params["password"]}) do
          {:ok, {user, _tokens}} ->
            user
            |> Accounts.User.confirm_changeset()
            |> WorkersUnite.Repo.update!()

            token = Accounts.generate_onboarding_session_token(user)

            {:noreply,
             socket
             |> assign(
               step: :session_handoff,
               handoff_form: to_form(%{"token" => token}, as: :onboarding_session),
               error: nil
             )}

          {:error, changeset} ->
            {:noreply, assign(socket, error: format_changeset_errors(changeset))}
        end

      {:error, :registration_closed} ->
        {:noreply, assign(socket, error: "An admin account already exists.")}

      {:error, changeset} ->
        {:noreply, assign(socket, error: format_changeset_errors(changeset))}
    end
  end

  def handle_event("skip_passkey", _params, socket) do
    {:noreply, complete_onboarding(socket)}
  end

  def handle_event("registered", _params, socket) do
    {:noreply, complete_onboarding(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="relative overflow-hidden rounded-[2rem] border border-base-300 bg-gradient-to-br from-base-100 via-base-100 to-base-200 shadow-xl">
        <div class="absolute inset-0 bg-[radial-gradient(circle_at_top_left,rgba(56,189,248,0.14),transparent_28%),radial-gradient(circle_at_bottom_right,rgba(251,191,36,0.14),transparent_30%)]" />

        <div class="relative grid gap-10 px-6 py-8 lg:grid-cols-[1.2fr_0.8fr] lg:px-10 lg:py-12">
          <section class="space-y-8">
            <div class="space-y-4">
              <div class="inline-flex items-center gap-2 rounded-full border border-base-300 bg-base-100/80 px-3 py-1 text-xs font-semibold uppercase tracking-[0.25em] text-base-content/60 shadow-sm">
                <.icon name="hero-sparkles" class="size-4 text-sky-500" /> Instance Setup
              </div>

              <div class="space-y-3">
                <h1 class="max-w-xl text-4xl font-black tracking-tight text-base-content sm:text-5xl">
                  Bring your first organizer online.
                </h1>
                <p class="max-w-2xl text-base leading-7 text-base-content/70 sm:text-lg">
                  Create the admin account that will configure the instance, approve settings, and
                  unlock your first agent workflows.
                </p>
              </div>
            </div>

            <div class="grid gap-4 sm:grid-cols-2">
              <div class="rounded-3xl border border-base-300 bg-base-100/80 p-5 shadow-sm">
                <div class="mb-3 flex items-center gap-3">
                  <span class="rounded-2xl bg-sky-500/10 p-2 text-sky-600">
                    <.icon name="hero-cpu-chip" class="size-5" />
                  </span>
                  <h3 class="font-semibold text-base-content">Agent Workbench</h3>
                </div>
                <p class="text-sm leading-6 text-base-content/65">
                  Launch agents that write code, review branches, and coordinate decisions across repositories.
                </p>
              </div>

              <div class="rounded-3xl border border-base-300 bg-base-100/80 p-5 shadow-sm">
                <div class="mb-3 flex items-center gap-3">
                  <span class="rounded-2xl bg-amber-500/10 p-2 text-amber-600">
                    <.icon name="hero-shield-check" class="size-5" />
                  </span>
                  <h3 class="font-semibold text-base-content">Cryptographic Trust</h3>
                </div>
                <p class="text-sm leading-6 text-base-content/65">
                  Protect access with password login now, then add passkeys for smoother, phishing-resistant sign-in.
                </p>
              </div>

              <div class="rounded-3xl border border-base-300 bg-base-100/80 p-5 shadow-sm">
                <div class="mb-3 flex items-center gap-3">
                  <span class="rounded-2xl bg-emerald-500/10 p-2 text-emerald-600">
                    <.icon name="hero-globe-alt" class="size-5" />
                  </span>
                  <h3 class="font-semibold text-base-content">Federated by Design</h3>
                </div>
                <p class="text-sm leading-6 text-base-content/65">
                  Coordinate with other instances through signed events and durable append-only history.
                </p>
              </div>

              <div class="rounded-3xl border border-base-300 bg-base-100/80 p-5 shadow-sm">
                <div class="mb-3 flex items-center gap-3">
                  <span class="rounded-2xl bg-fuchsia-500/10 p-2 text-fuchsia-600">
                    <.icon name="hero-chat-bubble-left-right" class="size-5" />
                  </span>
                  <h3 class="font-semibold text-base-content">Consensus Controls</h3>
                </div>
                <p class="text-sm leading-6 text-base-content/65">
                  Tune policies later for voting, approvals, and model defaults once the admin account is live.
                </p>
              </div>
            </div>
          </section>

          <section class="rounded-[1.75rem] border border-base-300 bg-base-100/90 p-6 shadow-lg backdrop-blur sm:p-8">
            <%= if @step == :account do %>
              <div class="space-y-6">
                <div class="space-y-2">
                  <p class="text-sm font-semibold uppercase tracking-[0.2em] text-base-content/50">
                    Step 1 of 2
                  </p>
                  <h2 class="text-2xl font-bold text-base-content">Create Admin Account</h2>
                  <p class="text-sm leading-6 text-base-content/65">
                    This first account becomes the admin for the instance. Passkeys can be added in the next step.
                  </p>
                </div>

                <div
                  :if={@error}
                  class="rounded-2xl border border-error/30 bg-error/10 px-4 py-3 text-sm text-error"
                >
                  {@error}
                </div>

                <.form
                  for={@form}
                  id="onboarding-account-form"
                  phx-submit="create_account"
                  class="space-y-4"
                >
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

                  <.button type="submit" class="w-full">
                    Create admin account
                  </.button>
                </.form>

                <p class="text-xs leading-5 text-base-content/50">
                  You can configure providers, model defaults, and agent settings after setup finishes.
                </p>
              </div>
            <% end %>

            <%= if @step == :session_handoff do %>
              <div
                id="onboarding-session-handoff"
                phx-hook=".AutoSubmitOnboardingSession"
                class="space-y-5"
              >
                <div class="space-y-2">
                  <p class="text-sm font-semibold uppercase tracking-[0.2em] text-base-content/50">
                    Preparing step 2
                  </p>
                  <h2 class="text-2xl font-bold text-base-content">Starting your secure session</h2>
                  <p class="text-sm leading-6 text-base-content/65">
                    One moment while we establish the browser session needed for passkey registration.
                  </p>
                </div>

                <div class="flex items-center gap-3 rounded-2xl border border-base-300 bg-base-200/70 px-4 py-3 text-sm text-base-content/70">
                  <.icon name="hero-arrow-path" class="size-5 animate-spin text-sky-500" />
                  Redirecting to the passkey step...
                </div>

                <.form
                  :if={@handoff_form}
                  for={@handoff_form}
                  id="onboarding-session-form"
                  action={~p"/onboarding/session"}
                  method="post"
                  class="space-y-3"
                >
                  <input
                    type="hidden"
                    name={@handoff_form[:token].name}
                    value={@handoff_form[:token].value}
                  />

                  <.button type="submit" class="w-full">
                    Continue to passkey setup
                  </.button>
                </.form>
              </div>
            <% end %>

            <%= if @step == :passkey do %>
              <div class="space-y-6">
                <div class="space-y-2">
                  <p class="text-sm font-semibold uppercase tracking-[0.2em] text-base-content/50">
                    Step 2 of 2
                  </p>
                  <h2 class="text-2xl font-bold text-base-content">Add a passkey</h2>
                  <p class="text-sm leading-6 text-base-content/65">
                    Passkeys are optional, but recommended. You can skip this now and add one later from settings.
                  </p>
                </div>

                <div class="rounded-3xl border border-base-300 bg-base-200/70 p-5">
                  <div class="mb-4 flex items-start gap-3">
                    <span class="mt-1 rounded-2xl bg-sky-500/10 p-2 text-sky-600">
                      <.icon name="hero-key" class="size-5" />
                    </span>
                    <div class="space-y-2">
                      <h3 class="font-semibold text-base-content">
                        Register a passkey for this browser or device
                      </h3>
                      <p class="text-sm leading-6 text-base-content/65">
                        Use Face ID, Touch ID, Windows Hello, or a hardware security key to sign in without typing your password.
                      </p>
                    </div>
                  </div>

                  <div class="flex flex-col gap-3 sm:flex-row">
                    <button
                      id="onboarding-passkey-register-btn"
                      type="button"
                      class="btn btn-primary sm:flex-1"
                      phx-hook="PasskeyRegistration"
                      data-label="Register passkey"
                    >
                      Register passkey
                    </button>

                    <.button
                      id="onboarding-skip-passkey-btn"
                      type="button"
                      phx-click="skip_passkey"
                      class="btn btn-ghost sm:flex-1"
                    >
                      Skip for now
                    </.button>
                  </div>
                </div>
              </div>
            <% end %>
          </section>
        </div>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".AutoSubmitOnboardingSession">
        export default {
          mounted() {
            requestAnimationFrame(() => {
              const form = this.el.querySelector("form")
              if (form) form.requestSubmit()
            })
          }
        }
      </script>
    </Layouts.app>
    """
  end

  defp onboarding_step(%{user: _user}), do: :passkey
  defp onboarding_step(_), do: :account

  defp complete_onboarding(socket) do
    user = socket.assigns.current_scope.user

    {:ok, _user} = Accounts.complete_onboarding(user)
    {:ok, _settings} = Settings.complete_onboarding(user.id)

    socket
    |> put_flash(:info, "Setup complete.")
    |> redirect(to: ~p"/")
  end

  defp account_form do
    to_form(%{"email" => "", "password" => ""}, as: "user")
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
