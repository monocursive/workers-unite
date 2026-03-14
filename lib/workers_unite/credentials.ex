defmodule WorkersUnite.Credentials do
  @moduledoc """
  Context for encrypted runtime credential CRUD.
  """

  import Ecto.Query
  alias WorkersUnite.Repo
  alias WorkersUnite.Credentials.{RuntimeCredential, Encryption}

  @doc """
  Upserts a credential (insert or update by provider+key_name).
  """
  def upsert(provider, key_name, plaintext_value, user_id \\ nil) do
    encrypted = Encryption.encrypt(plaintext_value)
    now = DateTime.utc_now(:second)

    %RuntimeCredential{}
    |> RuntimeCredential.changeset(%{
      provider: provider,
      key_name: key_name,
      encrypted_value: encrypted,
      created_by: user_id,
      updated_by: user_id
    })
    |> Repo.insert(
      on_conflict: [set: [encrypted_value: encrypted, updated_by: user_id, updated_at: now]],
      conflict_target: [:provider, :key_name],
      returning: true
    )
  end

  @doc """
  Lists all credentials (encrypted values not decrypted).
  """
  def list do
    Repo.all(from(c in RuntimeCredential, order_by: [asc: c.provider, asc: c.key_name]))
  end

  @doc """
  Deletes a credential by id.
  """
  def delete(id) do
    case Repo.get(RuntimeCredential, id) do
      nil -> {:error, :not_found}
      credential -> Repo.delete(credential)
    end
  end

  @doc """
  Gets and decrypts a single credential value.
  """
  def get_decrypted(provider, key_name) do
    case Repo.get_by(RuntimeCredential, provider: provider, key_name: key_name) do
      nil ->
        nil

      %{encrypted_value: encrypted} ->
        case Encryption.decrypt(encrypted) do
          {:ok, value} -> value
          :error -> nil
        end
    end
  end

  @doc """
  Returns all decrypted credentials for a provider as a map of `%{key_name => value}`.
  """
  def all_decrypted_for_provider(provider, repo_opts \\ []) do
    from(c in RuntimeCredential, where: c.provider == ^to_string(provider))
    |> Repo.all(repo_opts)
    |> Enum.reduce(%{}, fn %{key_name: key, encrypted_value: enc}, acc ->
      case Encryption.decrypt(enc) do
        {:ok, value} -> Map.put(acc, key, value)
        :error -> acc
      end
    end)
  end
end
