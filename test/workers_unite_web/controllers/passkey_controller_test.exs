defmodule WorkersUniteWeb.PasskeyControllerTest do
  use WorkersUniteWeb.ConnCase, async: true

  import WorkersUnite.AccountsFixtures

  describe "passkey registration endpoints" do
    test "registration challenge returns unauthorized json when unauthenticated", %{conn: conn} do
      conn = post(conn, ~p"/users/passkey-register/challenge")

      assert json_response(conn, 401) == %{"error" => "unauthorized"}
    end

    test "register returns unauthorized json when unauthenticated", %{conn: conn} do
      conn =
        post(conn, ~p"/users/passkey-register", %{
          "token" => "token",
          "attestation" => %{}
        })

      assert json_response(conn, 401) == %{"error" => "unauthorized"}
    end

    test "registration challenge is available before onboarding completes", %{conn: conn} do
      user = user_fixture()

      conn =
        conn
        |> log_in_user(user)
        |> post(~p"/users/passkey-register/challenge")

      response = json_response(conn, 200)

      assert is_binary(response["token"])
      assert is_map(response["options"])
      assert response["options"]["challenge"]
    end

    test "register returns json when attestation verification fails", %{conn: conn} do
      user = user_fixture()

      challenge_conn =
        conn
        |> log_in_user(user)
        |> post(~p"/users/passkey-register/challenge")

      %{"token" => token} = json_response(challenge_conn, 200)

      conn =
        challenge_conn
        |> recycle()
        |> post(~p"/users/passkey-register", %{
          "token" => token,
          "attestation" => %{
            "rawId" => url_encode("credential-id"),
            "attestationObject" => url_encode("bad-attestation"),
            "clientDataJSON" => url_encode("{}"),
            "transports" => []
          }
        })

      response = json_response(conn, 422)
      assert is_binary(response["error"])
      assert response["error"] != ""
    end
  end

  describe "passkey login endpoints" do
    test "email-scoped login rejects credentials from a different user", %{conn: conn} do
      scoped_user = user_fixture()
      other_user = user_fixture()
      other_credential = webauthn_credential_fixture(other_user)

      challenge_conn =
        post(conn, ~p"/users/passkey-login/challenge", %{"email" => scoped_user.email})

      %{"token" => token} = json_response(challenge_conn, 200)

      conn =
        challenge_conn
        |> recycle()
        |> post(~p"/users/passkey-login", %{
          "token" => token,
          "assertion" => %{
            "rawId" => url_encode(other_credential.credential_id),
            "authenticatorData" => url_encode("bad-auth-data"),
            "clientDataJSON" => url_encode("{}"),
            "signature" => url_encode("bad-signature")
          }
        })

      assert json_response(conn, 401) == %{"error" => "credential_scope_mismatch"}
      refute get_session(conn, :user_token)
    end

    test "login returns json when assertion verification fails", %{conn: conn} do
      user = user_fixture()
      credential = webauthn_credential_fixture(user)

      challenge_conn = post(conn, ~p"/users/passkey-login/challenge", %{"email" => user.email})
      %{"token" => token} = json_response(challenge_conn, 200)

      conn =
        challenge_conn
        |> recycle()
        |> post(~p"/users/passkey-login", %{
          "token" => token,
          "assertion" => %{
            "rawId" => url_encode(credential.credential_id),
            "authenticatorData" => url_encode("bad-auth-data"),
            "clientDataJSON" => url_encode("{}"),
            "signature" => url_encode("bad-signature")
          }
        })

      response = json_response(conn, 401)
      assert is_binary(response["error"])
      assert response["error"] != ""
      refute get_session(conn, :user_token)
    end
  end

  describe "passkey reauth endpoints" do
    test "reauth returns json when assertion verification fails", %{conn: conn} do
      user = onboarded_user_fixture()
      credential = webauthn_credential_fixture(user)

      challenge_conn =
        conn
        |> log_in_user(user)
        |> post(~p"/users/passkey-reauth/challenge")

      %{"token" => token} = json_response(challenge_conn, 200)

      conn =
        challenge_conn
        |> recycle()
        |> post(~p"/users/passkey-reauth", %{
          "token" => token,
          "assertion" => %{
            "rawId" => url_encode(credential.credential_id),
            "authenticatorData" => url_encode("bad-auth-data"),
            "clientDataJSON" => url_encode("{}"),
            "signature" => url_encode("bad-signature")
          }
        })

      response = json_response(conn, 401)
      assert is_binary(response["error"])
      assert response["error"] != ""
    end
  end

  defp url_encode(value) when is_binary(value), do: Base.url_encode64(value, padding: false)
end
