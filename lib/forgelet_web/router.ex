defmodule ForgeletWeb.Router do
  @moduledoc false

  use ForgeletWeb, :router

  import ForgeletWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ForgeletWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/mcp", ForgeletWeb.MCP do
    pipe_through :api

    post "/:token", Plug, []
  end

  # Unauthenticated health check for load balancers and container orchestrators
  scope "/", ForgeletWeb do
    pipe_through :api

    get "/health", HealthController, :show
  end

  # Registration (redirect if already authenticated)
  scope "/", ForgeletWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    get "/users/register", UserRegistrationController, :new
    post "/users/register", UserRegistrationController, :create
  end

  # Login routes (accessible to both authenticated and unauthenticated)
  scope "/", ForgeletWeb do
    pipe_through [:browser]

    get "/users/log-in", UserSessionController, :new
    post "/users/log-in", UserSessionController, :create
    get "/users/log-in/:token", UserSessionController, :confirm
    get "/users/onboarding-login/:token", UserSessionController, :onboarding_login
    delete "/users/log-out", UserSessionController, :delete
  end

  # Onboarding (special auth handling)
  scope "/", ForgeletWeb do
    pipe_through :browser

    live_session :onboarding,
      on_mount: [{ForgeletWeb.UserAuth, :ensure_authenticated_for_onboarding}] do
      live "/onboarding", OnboardingLive
    end
  end

  # Authenticated routes (require login + completed onboarding)
  scope "/", ForgeletWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/users/settings", UserSettingsController, :edit
    put "/users/settings", UserSettingsController, :update
    get "/users/settings/confirm-email/:token", UserSettingsController, :confirm_email

    live_session :authenticated,
      on_mount: [{ForgeletWeb.UserAuth, :ensure_authenticated}] do
      live "/", DashboardLive
      live "/events", EventFeedLive
      live "/agents", AgentListLive
      live "/agents/:id", AgentDetailLive
      live "/repos", RepoListLive
      live "/repos/:id", RepoDetailLive
      live "/consensus", ConsensusLive
    end

    live_session :admin,
      on_mount: [{ForgeletWeb.UserAuth, :ensure_admin}] do
      live "/settings", SettingsLive
      live "/settings/credentials", Settings.CredentialsLive
      live "/settings/personality", Settings.PersonalityLive
    end
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:forgelet, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: ForgeletWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
