defmodule WorkersUnite.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `WorkersUnite.Accounts` context.
  """

  import Ecto.Query

  alias WorkersUnite.Accounts
  alias WorkersUnite.Accounts.Scope

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"
  def valid_user_password, do: "hello world!"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email()
    })
  end

  def unconfirmed_user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> Accounts.register_user()

    user
  end

  def user_fixture(attrs \\ %{}) do
    user = unconfirmed_user_fixture(attrs)

    # Directly confirm the user instead of going through magic link
    user
    |> Accounts.User.confirm_changeset()
    |> WorkersUnite.Repo.update!()
  end

  def onboarded_user_fixture(attrs \\ %{}) do
    user = user_fixture(attrs)

    # Complete onboarding on user
    {:ok, user} = Accounts.complete_onboarding(user)

    # Complete onboarding at instance level
    WorkersUnite.Settings.complete_onboarding(user.id)

    user
  end

  def user_scope_fixture do
    user = user_fixture()
    user_scope_fixture(user)
  end

  def user_scope_fixture(user) do
    Scope.for_user(user)
  end

  def set_password(user) do
    {:ok, {user, _expired_tokens}} =
      Accounts.update_user_password(user, %{password: valid_user_password()})

    user
  end

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end

  def override_token_authenticated_at(token, authenticated_at) when is_binary(token) do
    WorkersUnite.Repo.update_all(
      from(t in Accounts.UserToken,
        where: t.token == ^token
      ),
      set: [authenticated_at: authenticated_at]
    )
  end

  def offset_user_token(token, amount_to_add, unit) do
    dt = DateTime.add(DateTime.utc_now(:second), amount_to_add, unit)

    WorkersUnite.Repo.update_all(
      from(ut in Accounts.UserToken, where: ut.token == ^token),
      set: [inserted_at: dt, authenticated_at: dt]
    )
  end

  @doc """
  Creates a WebauthnCredential directly in the DB for the given user.

  Useful for testing credential listing, renaming, deletion, and
  passkey-related UI without going through the full WebAuthn registration flow.
  """
  def webauthn_credential_fixture(user, attrs \\ %{}) do
    defaults = %{
      credential_id: :crypto.strong_rand_bytes(32),
      public_key:
        :erlang.term_to_binary(%{
          1 => 2,
          3 => -7,
          -1 => 1,
          -2 => :crypto.strong_rand_bytes(32),
          -3 => :crypto.strong_rand_bytes(32)
        }),
      sign_count: 0,
      transports: ["internal"],
      friendly_name: "Test Passkey",
      user_id: user.id
    }

    {:ok, credential} =
      %WorkersUnite.Accounts.WebauthnCredential{}
      |> WorkersUnite.Accounts.WebauthnCredential.changeset(Map.merge(defaults, attrs))
      |> WorkersUnite.Repo.insert()

    credential
  end
end
