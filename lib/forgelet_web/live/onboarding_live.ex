defmodule ForgeletWeb.OnboardingLive do
  use ForgeletWeb, :live_view

  @moduledoc """
  First-run onboarding wizard that guides the admin through creating an account,
  configuring API credentials, setting the orchestrator personality, and completing setup.
  """

  alias Forgelet.{Accounts, Credentials, Settings}

  @impl true
  def mount(_params, _session, socket) do
    step =
      cond do
        Accounts.first_user?() -> :account
        socket.assigns[:current_scope] -> :api_keys
        true -> :account
      end

    runtime_registry = Application.get_env(:forgelet, :runtime_registry, %{})

    providers =
      Enum.map(runtime_registry, fn {name, config} ->
        cred_keys = Map.keys(config[:credentials] || %{})
        {name, cred_keys}
      end)

    {:ok,
     assign(socket,
       page_title: "Setup Forgelet",
       step: step,
       providers: providers,
       account_form: to_form(%{"email" => "", "password" => ""}, as: "user"),
       credential_forms: %{},
       personality_form: to_form(%{"personality" => ""}, as: "settings"),
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
            |> Forgelet.Repo.update!()

            # Generate a one-time login token and redirect through controller
            # to properly establish the session cookie
            token = Accounts.generate_login_token(user)
            {:noreply, redirect(socket, to: ~p"/users/onboarding-login/#{token}")}

          {:error, changeset} ->
            error = format_changeset_errors(changeset)
            {:noreply, assign(socket, error: error)}
        end

      {:error, :registration_closed} ->
        {:noreply, assign(socket, error: "An admin account already exists.")}

      {:error, changeset} ->
        error = format_changeset_errors(changeset)
        {:noreply, assign(socket, error: error)}
    end
  end

  def handle_event("save_credentials", params, socket) do
    user_id =
      if socket.assigns[:current_scope],
        do: socket.assigns.current_scope.user.id,
        else: nil

    Enum.each(params, fn {key, value} ->
      if String.contains?(key, "|") and value != "" do
        [provider, key_name] = String.split(key, "|", parts: 2)
        Credentials.upsert(provider, key_name, value, user_id)
      end
    end)

    # Reload credential store
    try do
      Forgelet.CredentialStore.reload()
    catch
      _, _ -> :ok
    end

    {:noreply, assign(socket, step: :personality, error: nil)}
  end

  def handle_event("skip_credentials", _params, socket) do
    {:noreply, assign(socket, step: :personality)}
  end

  def handle_event("save_personality", %{"settings" => params}, socket) do
    user_id =
      if socket.assigns[:current_scope],
        do: socket.assigns.current_scope.user.id,
        else: nil

    personality = params["personality"]

    if personality && personality != "" do
      Settings.update(%{master_plan_personality: personality}, user_id)
    end

    {:noreply, assign(socket, step: :done, error: nil)}
  end

  def handle_event("skip_personality", _params, socket) do
    {:noreply, assign(socket, step: :done)}
  end

  def handle_event("complete_onboarding", _params, socket) do
    scope = socket.assigns[:current_scope]
    user_id = if scope, do: scope.user.id, else: nil

    Settings.complete_onboarding(user_id)

    if scope do
      Accounts.complete_onboarding(scope.user)
    end

    {:noreply, redirect(socket, to: ~p"/")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center px-4">
      <div class="w-full max-w-lg space-y-8">
        <div class="text-center">
          <h1 class="text-3xl font-bold text-primary">Forgelet Setup</h1>
          <p class="text-sm opacity-70 mt-2">
            Step {step_number(@step)} of 4
          </p>
          <div class="flex gap-2 justify-center mt-4">
            <div
              :for={s <- [:account, :api_keys, :personality, :done]}
              class={"w-16 h-1 rounded-full #{if step_index(s) <= step_index(@step), do: "bg-primary", else: "bg-base-300"}"}
            />
          </div>
        </div>

        <div :if={@error} class="alert alert-error text-sm">{@error}</div>

        <%= case @step do %>
          <% :account -> %>
            <.account_step form={@account_form} />
          <% :api_keys -> %>
            <.api_keys_step providers={@providers} />
          <% :personality -> %>
            <.personality_step form={@personality_form} />
          <% :done -> %>
            <.done_step />
        <% end %>
      </div>
    </div>
    """
  end

  defp account_step(assigns) do
    ~H"""
    <div class="card bg-base-200 p-6 space-y-4">
      <h2 class="text-xl font-semibold">Create Admin Account</h2>
      <p class="text-sm opacity-70">This will be the first and only admin account.</p>
      <form phx-submit="create_account" class="space-y-4">
        <div class="form-control">
          <label class="label">Email</label>
          <input
            type="email"
            name="user[email]"
            value={@form["email"].value}
            required
            class="input input-bordered w-full"
            placeholder="admin@example.com"
          />
        </div>
        <div class="form-control">
          <label class="label">Password</label>
          <input
            type="password"
            name="user[password]"
            required
            minlength="12"
            class="input input-bordered w-full"
            placeholder="At least 12 characters"
          />
        </div>
        <button type="submit" class="btn btn-primary w-full">Create Account</button>
      </form>
    </div>
    """
  end

  defp api_keys_step(assigns) do
    ~H"""
    <div class="card bg-base-200 p-6 space-y-4">
      <h2 class="text-xl font-semibold">API Keys</h2>
      <p class="text-sm opacity-70">
        Configure credentials for AI runtime providers. You can skip this and set them later in Settings.
      </p>
      <form phx-submit="save_credentials" class="space-y-4">
        <div :for={{provider, keys} <- @providers} class="space-y-2">
          <h3 class="font-medium text-sm">{provider}</h3>
          <div :for={key <- keys} class="form-control">
            <label class="label text-xs opacity-70">{key}</label>
            <input
              type="password"
              name={"#{provider}|#{key}"}
              class="input input-bordered input-sm w-full"
              placeholder={"Enter #{key}"}
            />
          </div>
          <p :if={keys == []} class="text-xs opacity-50">
            No credentials configured for this provider.
          </p>
        </div>
        <div class="flex gap-2">
          <button type="submit" class="btn btn-primary flex-1">Save & Continue</button>
          <button type="button" phx-click="skip_credentials" class="btn btn-ghost">Skip</button>
        </div>
      </form>
    </div>
    """
  end

  defp personality_step(assigns) do
    ~H"""
    <div class="card bg-base-200 p-6 space-y-4">
      <h2 class="text-xl font-semibold">Master Plan Personality</h2>
      <p class="text-sm opacity-70">
        Provide high-level directives that will be injected into orchestrator agent prompts.
        This shapes how your agents coordinate and prioritize work.
      </p>
      <form phx-submit="save_personality" class="space-y-4">
        <div class="form-control">
          <textarea
            name="settings[personality]"
            class="textarea textarea-bordered w-full h-32"
            placeholder="e.g., Prioritize test coverage. Prefer small, focused PRs. Always run benchmarks before proposing performance changes."
          >{@form["personality"].value}</textarea>
        </div>
        <div class="flex gap-2">
          <button type="submit" class="btn btn-primary flex-1">Save & Continue</button>
          <button type="button" phx-click="skip_personality" class="btn btn-ghost">Skip</button>
        </div>
      </form>
    </div>
    """
  end

  defp done_step(assigns) do
    ~H"""
    <div class="card bg-base-200 p-6 space-y-4 text-center">
      <h2 class="text-xl font-semibold">Setup Complete</h2>
      <p class="text-sm opacity-70">
        Your Forgelet instance is ready. You can always update these settings later from the Settings page.
      </p>
      <button phx-click="complete_onboarding" class="btn btn-primary btn-lg">
        Launch Forgelet
      </button>
    </div>
    """
  end

  defp step_number(:account), do: 1
  defp step_number(:api_keys), do: 2
  defp step_number(:personality), do: 3
  defp step_number(:done), do: 4

  defp step_index(:account), do: 0
  defp step_index(:api_keys), do: 1
  defp step_index(:personality), do: 2
  defp step_index(:done), do: 3

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.map_join(", ", fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)
  end
end
