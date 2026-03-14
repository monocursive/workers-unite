defmodule WorkersUniteWeb.Router do
  @moduledoc false

  use WorkersUniteWeb, :router

  import WorkersUniteWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {WorkersUniteWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :browser_json do
    plug :accepts, ["json"]
    plug :fetch_session
    plug :put_secure_browser_headers
    plug :protect_from_forgery
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/mcp", WorkersUniteWeb.MCP do
    pipe_through :api

    post "/:token", Plug, []
  end

  scope "/operator/mcp", WorkersUniteWeb.OperatorMCP do
    pipe_through :api

    match :*, "/*path", Plug, []
  end

  # Unauthenticated health check for load balancers and container orchestrators
  scope "/", WorkersUniteWeb do
    pipe_through :api

    get "/health", HealthController, :show
  end

  # Passkey login (unauthenticated JSON endpoints)
  scope "/users", WorkersUniteWeb do
    pipe_through [:browser_json]

    post "/passkey-login/challenge", PasskeyController, :login_challenge
    post "/passkey-login", PasskeyController, :login
  end

  # Passkey reauth (authenticated JSON endpoints, onboarding complete)
  scope "/users", WorkersUniteWeb do
    pipe_through [:browser_json, :require_authenticated_user]

    post "/passkey-reauth/challenge", PasskeyController, :reauth_challenge
    post "/passkey-reauth", PasskeyController, :reauth
  end

  # Passkey registration (authenticated session required, onboarding may be incomplete)
  scope "/users", WorkersUniteWeb do
    pipe_through [:browser_json, :require_session_user]

    post "/passkey-register/challenge", PasskeyController, :registration_challenge
    post "/passkey-register", PasskeyController, :register
  end

  # Operator token management (browser JSON, authenticated)
  scope "/operator", WorkersUniteWeb do
    pipe_through [:browser_json, :require_authenticated_user]

    get "/tokens", OperatorTokenController, :index
    post "/tokens", OperatorTokenController, :create
    delete "/tokens/:id", OperatorTokenController, :delete
  end

  # Registration redirects to onboarding
  scope "/", WorkersUniteWeb do
    pipe_through [:browser]

    get "/users/register", UserRegistrationController, :new
    post "/users/register", UserRegistrationController, :create
  end

  # Login routes (accessible to both authenticated and unauthenticated)
  scope "/", WorkersUniteWeb do
    pipe_through [:browser]

    get "/users/log-in", UserSessionController, :new
    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end

  # Onboarding session handoff route. It must use the browser pipeline because the
  # controller needs session and flash support before onboarding is complete.
  scope "/", WorkersUniteWeb do
    pipe_through [:browser]

    post "/onboarding/session", OnboardingSessionController, :create
  end

  # Onboarding (special auth handling)
  scope "/", WorkersUniteWeb do
    pipe_through :browser

    live_session :onboarding,
      on_mount: [{WorkersUniteWeb.UserAuth, :ensure_authenticated_for_onboarding}] do
      live "/onboarding", OnboardingLive
    end
  end

  # Authenticated routes (require login + completed onboarding)
  scope "/", WorkersUniteWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/users/settings", UserSettingsController, :edit
    put "/users/settings", UserSettingsController, :update
    get "/users/settings/confirm-email/:token", UserSettingsController, :confirm_email

    live_session :authenticated,
      on_mount: [{WorkersUniteWeb.UserAuth, :ensure_authenticated}] do
      live "/", DashboardLive
      live "/events", EventFeedLive
      live "/agents", AgentListLive
      live "/agents/:id", AgentDetailLive
      live "/repos", RepoListLive
      live "/repos/:id", RepoDetailLive
      live "/consensus", ConsensusLive
    end

    live_session :admin,
      on_mount: [{WorkersUniteWeb.UserAuth, :ensure_admin}] do
      live "/settings", SettingsLive
      live "/settings/model", Settings.ModelLive
      live "/settings/credentials", Settings.CredentialsLive
      live "/settings/personality", Settings.PersonalityLive
      live "/settings/operator", Settings.OperatorLive
    end

    live_session :passkey_settings,
      on_mount: [
        {WorkersUniteWeb.UserAuth, :ensure_authenticated},
        {WorkersUniteWeb.UserAuth, :ensure_sudo}
      ] do
      live "/users/settings/passkeys", Settings.PasskeysLive
    end
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:workers_unite, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: WorkersUniteWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
