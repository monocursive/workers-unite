defmodule WorkersUnite.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias WorkersUnite.Repo

  require Logger

  alias WorkersUnite.Accounts.{
    User,
    UserToken,
    UserNotifier,
    WebauthnCredential,
    WebauthnChallenge
  }

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  ## User registration

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    %User{}
    |> User.email_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Atomically registers the first user (admin). Returns `{:error, :registration_closed}`
  if any user already exists. Uses an advisory lock to prevent TOCTOU races.
  """
  @first_user_advisory_lock 736_501
  def register_first_user(attrs) do
    Repo.transact(fn ->
      Repo.query!("SELECT pg_advisory_xact_lock($1)", [@first_user_advisory_lock])

      if Repo.exists?(User) do
        {:error, :registration_closed}
      else
        %User{}
        |> User.email_changeset(attrs)
        |> Repo.insert()
      end
    end)
  end

  ## Onboarding

  @doc """
  Returns true if no users exist yet.
  """
  def first_user? do
    not Repo.exists?(User)
  end

  @doc """
  Returns true if onboarding is still required (no users exist).
  """
  def onboarding_required? do
    first_user?()
  end

  @doc """
  Marks the user as having completed onboarding.
  """
  def complete_onboarding(%User{} = user) do
    user
    |> Ecto.Changeset.change(onboarding_completed_at: DateTime.utc_now())
    |> Repo.update()
  end

  @doc """
  Generates a one-time onboarding session handoff token for the user.
  """
  def generate_onboarding_session_token(%User{} = user) do
    {encoded_token, user_token} = UserToken.build_onboarding_session_token(user)
    Repo.insert!(user_token)
    encoded_token
  end

  @doc """
  Consumes a one-time onboarding session handoff token and returns the user.
  """
  def consume_onboarding_session_token(token) do
    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_onboarding_session_token_query(token),
           %UserToken{} = user_token <- Repo.one(lock(query, "FOR UPDATE")),
           %User{} = user <- Repo.get(User, user_token.user_id) do
        Repo.delete!(user_token)
        {:ok, user}
      else
        nil -> {:error, :invalid_or_expired}
        :error -> {:error, :invalid_or_expired}
      end
    end)
  end

  ## Settings

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  See `WorkersUnite.Accounts.User.email_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: ^context])) do
        {:ok, user}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  See `WorkersUnite.Accounts.User.password_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user password.

  Returns a tuple with the updated user, as well as a list of expired tokens.

  ## Examples

      iex> update_user_password(user, %{password: ...})
      {:ok, {%User{}, [...]}}

      iex> update_user_password(user, %{password: "too short"})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens()
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm-email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## WebAuthn — Passkey Management

  @doc """
  Lists all WebAuthn credentials for the user in the given scope.
  """
  def list_webauthn_credentials(%{user: user}) do
    Repo.all(
      from c in WebauthnCredential, where: c.user_id == ^user.id, order_by: [asc: c.inserted_at]
    )
  end

  @doc """
  Gets a single WebAuthn credential, scoped to the user.
  Raises if not found.
  """
  def get_webauthn_credential!(%{user: user}, id) do
    Repo.get_by!(WebauthnCredential, id: id, user_id: user.id)
  end

  @doc """
  Generates a WebAuthn registration challenge for the given user scope.
  Returns `{:ok, token, options_map}` where options_map contains the
  publicKeyCredentialCreationOptions to send to the browser.
  """
  def generate_webauthn_registration_challenge(%{user: user}) do
    purge_expired_challenges()

    existing_credentials =
      Repo.all(
        from c in WebauthnCredential, where: c.user_id == ^user.id, select: c.credential_id
      )

    challenge =
      Wax.new_registration_challenge(
        attestation: "none",
        user_verification: "preferred",
        timeout: 120
      )

    # Replace any existing registration challenge for this user
    Repo.delete_all(
      from c in WebauthnChallenge, where: c.user_id == ^user.id and c.purpose == "registration"
    )

    {token, record} = WebauthnChallenge.build("registration", challenge, user.id)
    Repo.insert!(record)

    options = %{
      challenge: Base.url_encode64(challenge.bytes, padding: false),
      rp: %{name: "WorkersUnite", id: challenge.rp_id},
      user: %{
        id: Base.url_encode64(user.id, padding: false),
        name: user.email,
        displayName: user.email
      },
      pubKeyCredParams: [
        %{type: "public-key", alg: -7},
        %{type: "public-key", alg: -257}
      ],
      timeout: 120_000,
      attestation: "none",
      authenticatorSelection: %{
        residentKey: "preferred",
        userVerification: "preferred"
      },
      excludeCredentials:
        Enum.map(existing_credentials, fn cred_id ->
          %{type: "public-key", id: Base.url_encode64(cred_id, padding: false)}
        end)
    }

    {:ok, token, options}
  end

  @doc """
  Verifies and registers a WebAuthn credential from an attestation response.
  """
  def register_webauthn_credential(%{user: user}, token, attestation, friendly_name) do
    Repo.transact(fn ->
      with {:ok, query} <- WebauthnChallenge.consume_token_query(token, "registration"),
           %WebauthnChallenge{} = challenge_record <- Repo.one(lock(query, "FOR UPDATE")),
           :ok <- ensure_challenge_user_matches_user(challenge_record, user) do
        Repo.delete!(challenge_record)
        challenge = :erlang.binary_to_term(challenge_record.challenge_data, [:safe])

        with {:ok, attestation_object} <-
               Base.url_decode64(attestation["attestationObject"], padding: false),
             {:ok, client_data_json} <-
               Base.url_decode64(attestation["clientDataJSON"], padding: false),
             {:ok, raw_id} <- Base.url_decode64(attestation["rawId"], padding: false) do
          case safe_wax_register(attestation_object, client_data_json, challenge) do
            {:ok, {authenticator_data, _attestation_result}} ->
              %WebauthnCredential{}
              |> WebauthnCredential.changeset(%{
                credential_id: raw_id,
                public_key:
                  :erlang.term_to_binary(
                    authenticator_data.attested_credential_data.credential_public_key
                  ),
                sign_count: authenticator_data.sign_count,
                transports: attestation["transports"] || [],
                friendly_name: friendly_name || "Passkey",
                aaguid: authenticator_data.attested_credential_data.aaguid,
                user_id: user.id
              })
              |> Repo.insert()

            {:error, reason} ->
              {:error, reason}
          end
        else
          :error -> {:error, :invalid_attestation_encoding}
        end
      else
        nil -> {:error, :invalid_challenge}
        {:error, _} = error -> error
        :error -> {:error, :invalid_token}
      end
    end)
  end

  @doc """
  Renames a WebAuthn credential.
  """
  def rename_webauthn_credential(%{user: user}, id, name) do
    credential = Repo.get_by!(WebauthnCredential, id: id, user_id: user.id)

    credential
    |> WebauthnCredential.rename_changeset(%{friendly_name: name})
    |> Repo.update()
  end

  @doc """
  Deletes a WebAuthn credential. Refuses if it's the last passkey and the user has no password.
  """
  def delete_webauthn_credential(%{user: user}, id) do
    Repo.transact(fn ->
      locked_user =
        from(u in User, where: u.id == ^user.id)
        |> lock("FOR UPDATE")
        |> Repo.one!()

      credential = Repo.get_by!(WebauthnCredential, id: id, user_id: locked_user.id)

      credential_count =
        Repo.aggregate(from(c in WebauthnCredential, where: c.user_id == ^locked_user.id), :count)

      cond do
        credential_count <= 1 and is_nil(locked_user.hashed_password) ->
          {:error, :last_auth_factor}

        true ->
          Repo.delete(credential)
      end
    end)
  end

  ## WebAuthn — Login

  @doc """
  Generates a WebAuthn login challenge.
  If email is provided, scopes allowCredentials to that user's registered credentials.
  If email is nil, creates a discoverable credential challenge (no allowCredentials).
  """
  def generate_webauthn_login_challenge(email \\ nil) do
    purge_expired_challenges()

    {browser_credentials, user_id} =
      if email do
        case get_user_by_email(email) do
          nil ->
            {[], nil}

          user ->
            creds =
              Repo.all(
                from c in WebauthnCredential,
                  where: c.user_id == ^user.id,
                  select: {c.credential_id, c.transports}
              )

            {creds, user.id}
        end
      else
        {[], nil}
      end

    challenge =
      Wax.new_authentication_challenge(
        user_verification: "preferred",
        timeout: 120
      )

    # Replace any existing login challenge for this user (if scoped)
    if user_id do
      Repo.delete_all(
        from c in WebauthnChallenge, where: c.user_id == ^user_id and c.purpose == "login"
      )
    end

    {token, record} = WebauthnChallenge.build("login", challenge, user_id)
    Repo.insert!(record)

    options = %{
      challenge: Base.url_encode64(challenge.bytes, padding: false),
      rpId: challenge.rp_id,
      timeout: 120_000,
      userVerification: "preferred"
    }

    options =
      if browser_credentials != [] do
        Map.put(
          options,
          :allowCredentials,
          Enum.map(browser_credentials, fn {cred_id, transports} ->
            entry = %{type: "public-key", id: Base.url_encode64(cred_id, padding: false)}
            if (transports || []) != [], do: Map.put(entry, :transports, transports), else: entry
          end)
        )
      else
        options
      end

    {:ok, token, options}
  end

  @doc """
  Verifies a WebAuthn login assertion and returns the authenticated user.
  """
  def verify_webauthn_login(token, assertion) do
    Repo.transact(fn ->
      case do_consume_and_verify(token, "login", assertion) do
        {:ok, user} ->
          # For discoverable login, verify userHandle matches the resolved user
          if assertion["userHandle"] do
            case Base.url_decode64(assertion["userHandle"], padding: false) do
              {:ok, user_handle} ->
                if user_handle == user.id,
                  do: {:ok, user},
                  else: {:error, :user_handle_mismatch}

              :error ->
                {:error, :invalid_user_handle}
            end
          else
            {:ok, user}
          end

        error ->
          error
      end
    end)
  end

  ## WebAuthn — Reauth

  @doc """
  Generates a WebAuthn reauth challenge, scoped to the current user's credentials.
  """
  def generate_webauthn_reauth_challenge(%{user: user}) do
    purge_expired_challenges()

    creds =
      Repo.all(
        from c in WebauthnCredential,
          where: c.user_id == ^user.id,
          select: {c.credential_id, c.transports}
      )

    challenge =
      Wax.new_authentication_challenge(
        user_verification: "preferred",
        timeout: 120
      )

    # Replace any existing reauth challenge for this user
    Repo.delete_all(
      from c in WebauthnChallenge, where: c.user_id == ^user.id and c.purpose == "reauth"
    )

    {token, record} = WebauthnChallenge.build("reauth", challenge, user.id)
    Repo.insert!(record)

    options = %{
      challenge: Base.url_encode64(challenge.bytes, padding: false),
      rpId: challenge.rp_id,
      timeout: 120_000,
      userVerification: "preferred",
      allowCredentials:
        Enum.map(creds, fn {cred_id, transports} ->
          entry = %{type: "public-key", id: Base.url_encode64(cred_id, padding: false)}
          if (transports || []) != [], do: Map.put(entry, :transports, transports), else: entry
        end)
    }

    {:ok, token, options}
  end

  @doc """
  Verifies a WebAuthn reauth assertion. The assertion must resolve to the same user as the scope.
  """
  def verify_webauthn_reauth(%{user: user}, token, assertion) do
    Repo.transact(fn ->
      case do_consume_and_verify(token, "reauth", assertion) do
        {:ok, authed_user} ->
          if authed_user.id == user.id, do: {:ok, authed_user}, else: {:error, :wrong_user}

        error ->
          error
      end
    end)
  end

  # Consumes a challenge token and verifies a WebAuthn assertion.
  # Must be called inside a Repo.transact block.
  defp do_consume_and_verify(token, purpose, assertion) do
    with {:ok, query} <- WebauthnChallenge.consume_token_query(token, purpose),
         %WebauthnChallenge{} = challenge_record <- Repo.one(lock(query, "FOR UPDATE")) do
      Repo.delete!(challenge_record)
      challenge = :erlang.binary_to_term(challenge_record.challenge_data, [:safe])

      with {:ok, raw_id} <- Base.url_decode64(assertion["rawId"], padding: false),
           %WebauthnCredential{} = credential <-
             Repo.get_by(WebauthnCredential, credential_id: raw_id),
           :ok <- ensure_challenge_user_matches_credential(challenge_record, credential),
           {:ok, authenticator_data} <-
             Base.url_decode64(assertion["authenticatorData"], padding: false),
           {:ok, client_data_json} <-
             Base.url_decode64(assertion["clientDataJSON"], padding: false),
           {:ok, signature} <- Base.url_decode64(assertion["signature"], padding: false) do
        do_verify_assertion(
          credential,
          authenticator_data,
          client_data_json,
          signature,
          raw_id,
          challenge
        )
      else
        nil -> {:error, :credential_not_found}
        {:error, _} = error -> error
        :error -> {:error, :invalid_assertion_encoding}
      end
    else
      nil -> {:error, :invalid_challenge}
      :error -> {:error, :invalid_token}
    end
  end

  defp do_verify_assertion(
         credential,
         authenticator_data,
         client_data_json,
         signature,
         raw_id,
         challenge
       ) do
    public_key = :erlang.binary_to_term(credential.public_key, [:safe])

    case safe_wax_authenticate(
           raw_id,
           authenticator_data,
           signature,
           client_data_json,
           challenge,
           [{credential.credential_id, public_key}]
         ) do
      {:ok, auth_data} ->
        # Detect cloned authenticators via sign count regression
        if auth_data.sign_count > 0 and auth_data.sign_count <= credential.sign_count do
          Logger.warning("Possible cloned authenticator detected",
            credential_id: Base.encode16(credential.credential_id),
            stored_count: credential.sign_count,
            received_count: auth_data.sign_count
          )

          {:error, :cloned_authenticator}
        else
          credential
          |> Ecto.Changeset.change(
            sign_count: auth_data.sign_count,
            last_used_at: DateTime.utc_now() |> DateTime.truncate(:second)
          )
          |> Repo.update!()

          {:ok, get_user!(credential.user_id)}
        end

      {:error, reason} ->
        Logger.warning("WebAuthn assertion verification failed", reason: inspect(reason))
        {:error, reason}
    end
  end

  @doc """
  Returns true if the given user has any registered passkeys.
  """
  def has_passkeys?(user) do
    Repo.exists?(from c in WebauthnCredential, where: c.user_id == ^user.id)
  end

  ## Maintenance

  defp purge_expired_challenges do
    now = DateTime.utc_now()
    Repo.delete_all(from c in WebauthnChallenge, where: c.expires_at < ^now)
  end

  defp safe_wax_register(attestation_object, client_data_json, challenge) do
    Wax.register(attestation_object, client_data_json, challenge)
  rescue
    error -> {:error, error}
  end

  defp safe_wax_authenticate(
         raw_id,
         authenticator_data,
         signature,
         client_data_json,
         challenge,
         credentials
       ) do
    Wax.authenticate(
      raw_id,
      authenticator_data,
      signature,
      client_data_json,
      challenge,
      credentials
    )
  rescue
    error -> {:error, error}
  end

  defp ensure_challenge_user_matches_user(%WebauthnChallenge{user_id: user_id}, %User{id: user_id}),
       do: :ok

  defp ensure_challenge_user_matches_user(_challenge_record, _user),
    do: {:error, :challenge_scope_mismatch}

  defp ensure_challenge_user_matches_credential(%WebauthnChallenge{user_id: nil}, _credential),
    do: :ok

  defp ensure_challenge_user_matches_credential(
         %WebauthnChallenge{user_id: user_id},
         %WebauthnCredential{user_id: user_id}
       ),
       do: :ok

  defp ensure_challenge_user_matches_credential(_challenge_record, _credential),
    do: {:error, :credential_scope_mismatch}

  ## Token helper

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end
end
