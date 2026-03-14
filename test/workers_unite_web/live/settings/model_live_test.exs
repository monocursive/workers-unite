defmodule WorkersUniteWeb.Settings.ModelLiveTest do
  use WorkersUniteWeb.ConnCase

  import Phoenix.LiveViewTest

  alias WorkersUnite.{Settings, Credentials}

  setup :register_and_log_in_onboarded_user

  setup do
    WorkersUnite.CredentialStore.reload(caller: self())
    :ok
  end

  test "renders model settings page", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/settings/model")
    assert html =~ "Model Settings"
    assert html =~ "Available Models"
  end

  test "displays model catalog", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/settings/model")
    assert html =~ "Claude Sonnet 4"
    assert html =~ "GPT-4o"
  end

  test "shows provider status badges", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/settings/model")
    assert html =~ "key required"
  end

  test "shows configured badge when provider has key", %{conn: conn, user: user} do
    Credentials.upsert("anthropic", "ANTHROPIC_API_KEY", "test-key", user.id)
    WorkersUnite.CredentialStore.reload(caller: self())

    {:ok, _view, html} = live(conn, "/settings/model")
    assert html =~ "configured"
  end

  test "selects a model when provider is configured", %{conn: conn, user: user} do
    Credentials.upsert("anthropic", "ANTHROPIC_API_KEY", "test-key", user.id)
    WorkersUnite.CredentialStore.reload(caller: self())

    {:ok, view, _html} = live(conn, "/settings/model")

    html =
      view
      |> element("#model-claude-sonnet-4")
      |> render_click()

    assert html =~ "Default model updated to Claude Sonnet 4"

    assert Settings.get_default_agent_model() == "claude-sonnet-4"
  end

  test "blocks selection when provider not configured", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/settings/model")

    html =
      view
      |> element("#model-claude-sonnet-4")
      |> render_click()

    assert html =~ "Anthropic API key not configured"
    refute Settings.get_default_agent_model() == "claude-sonnet-4"
  end

  test "displays current selection", %{conn: conn, user: user} do
    Settings.set_default_agent_model("gpt-4o", user.id)

    {:ok, _view, html} = live(conn, "/settings/model")
    assert html =~ "gpt-4o"
  end

  test "shows link to credentials page", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/settings/model")
    assert has_element?(view, "#manage-credentials-link[href='/settings/credentials']")
  end
end
