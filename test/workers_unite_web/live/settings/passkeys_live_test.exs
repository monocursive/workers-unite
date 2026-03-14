defmodule WorkersUniteWeb.Settings.PasskeysLiveTest do
  use WorkersUniteWeb.ConnCase

  import Phoenix.LiveViewTest
  import WorkersUnite.AccountsFixtures

  # PasskeysLive requires :ensure_authenticated + :ensure_sudo on_mount.
  # The sudo check requires authenticated_at within the last 10 minutes.
  # Evaluate DateTime.utc_now at runtime (not compile time) to avoid flakiness.
  setup context do
    context
    |> Map.put(:token_authenticated_at, DateTime.utc_now(:second))
    |> register_and_log_in_onboarded_user()
  end

  describe "mount" do
    test "renders empty state when user has no passkeys", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/users/settings/passkeys")

      assert html =~ "Passkeys"
      assert html =~ "No passkeys registered yet"
    end

    test "renders credentials when present", %{conn: conn, user: user} do
      webauthn_credential_fixture(user, %{friendly_name: "My YubiKey"})
      webauthn_credential_fixture(user, %{friendly_name: "Phone"})

      {:ok, _view, html} = live(conn, ~p"/users/settings/passkeys")

      assert html =~ "My YubiKey"
      assert html =~ "Phone"
      refute html =~ "No passkeys registered yet"
    end
  end

  describe "rename" do
    test "start_rename shows an input with current name", %{conn: conn, user: user} do
      cred = webauthn_credential_fixture(user, %{friendly_name: "My Key"})

      {:ok, view, _html} = live(conn, ~p"/users/settings/passkeys")

      html =
        view
        |> element(~s(button[phx-click="start_rename"][phx-value-id="#{cred.id}"]))
        |> render_click()

      assert html =~ ~s(name="credential[friendly_name]")
      assert html =~ "Save"
      assert html =~ "Cancel"
    end

    test "cancel_rename hides the rename input", %{conn: conn, user: user} do
      cred = webauthn_credential_fixture(user, %{friendly_name: "My Key"})

      {:ok, view, _html} = live(conn, ~p"/users/settings/passkeys")

      view
      |> element(~s(button[phx-click="start_rename"][phx-value-id="#{cred.id}"]))
      |> render_click()

      html =
        view
        |> element(~s(button[phx-click="cancel_rename"]))
        |> render_click()

      refute html =~ ~s(name="credential[friendly_name]")
      assert html =~ "My Key"
    end

    test "save_rename updates the credential name", %{conn: conn, user: user} do
      cred = webauthn_credential_fixture(user, %{friendly_name: "Old Name"})

      {:ok, view, _html} = live(conn, ~p"/users/settings/passkeys")

      view
      |> element(~s(button[phx-click="start_rename"][phx-value-id="#{cred.id}"]))
      |> render_click()

      html =
        view
        |> form(~s(form[phx-submit="save_rename"]), credential: %{friendly_name: "New Name"})
        |> render_submit()

      assert html =~ "New Name"
      refute html =~ "Old Name"
    end
  end

  describe "delete" do
    test "removes a credential when user has a password", %{user: user} do
      # set_password deletes all tokens, so we need to re-establish the session
      user = set_password(user)
      cred = webauthn_credential_fixture(user, %{friendly_name: "Deletable Key"})

      conn =
        build_conn()
        |> log_in_user(user, token_authenticated_at: DateTime.utc_now(:second))

      {:ok, view, _html} = live(conn, ~p"/users/settings/passkeys")

      html =
        view
        |> element(~s(button[phx-click="delete"][phx-value-id="#{cred.id}"]))
        |> render_click()

      assert html =~ "Passkey deleted."
      refute html =~ "Deletable Key"
    end

    test "removes a credential when user has multiple passkeys and no password", %{
      conn: conn,
      user: user
    } do
      cred1 = webauthn_credential_fixture(user, %{friendly_name: "Key One"})
      _cred2 = webauthn_credential_fixture(user, %{friendly_name: "Key Two"})

      {:ok, view, _html} = live(conn, ~p"/users/settings/passkeys")

      html =
        view
        |> element(~s(button[phx-click="delete"][phx-value-id="#{cred1.id}"]))
        |> render_click()

      assert html =~ "Passkey deleted."
      refute html =~ "Key One"
      assert html =~ "Key Two"
    end

    test "shows error when deleting last credential with no password", %{conn: conn, user: user} do
      cred = webauthn_credential_fixture(user, %{friendly_name: "Only Key"})

      {:ok, view, _html} = live(conn, ~p"/users/settings/passkeys")

      html =
        view
        |> element(~s(button[phx-click="delete"][phx-value-id="#{cred.id}"]))
        |> render_click()

      assert html =~ "Cannot delete your only passkey when no password is set."
      assert html =~ "Only Key"
    end
  end

  describe "registered event" do
    test "refreshes the credential list", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/users/settings/passkeys")

      # Simulate a credential being registered externally (e.g. via JS hook)
      webauthn_credential_fixture(user, %{friendly_name: "Fresh Key"})

      html = render_hook(view, "registered", %{})

      assert html =~ "Fresh Key"
      assert html =~ "Passkey registered."
    end
  end

  describe "authentication requirements" do
    test "redirects unauthenticated users to login", %{conn: _conn} do
      conn = build_conn()

      assert {:error, {:redirect, %{to: "/users/log-in"}}} =
               live(conn, ~p"/users/settings/passkeys")
    end

    test "redirects when sudo mode has expired" do
      user = onboarded_user_fixture()

      conn =
        build_conn()
        |> log_in_user(user,
          token_authenticated_at: DateTime.add(DateTime.utc_now(:second), -15, :minute)
        )

      assert {:error, {:redirect, %{to: "/users/log-in"}}} =
               live(conn, ~p"/users/settings/passkeys")
    end
  end
end
