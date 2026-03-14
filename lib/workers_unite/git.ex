defmodule WorkersUnite.Git do
  @moduledoc """
  Thin wrappers around git commands used by WorkersUnite workflows.
  """

  @default_branch "main"

  def default_branch, do: @default_branch

  def clone(source, destination) do
    run(nil, ["clone", source, destination])
  end

  def fetch_all(repo_path) do
    run(repo_path, ["fetch", "--all", "--prune"])
  end

  def configure_identity(repo_path, name, email) do
    with :ok <- run(repo_path, ["config", "user.name", name]),
         :ok <- run(repo_path, ["config", "user.email", email]) do
      :ok
    end
  end

  def checkout_branch(repo_path, branch_name, start_point) do
    run(repo_path, ["checkout", "-B", branch_name, start_point])
  end

  def checkout_existing_branch(repo_path, branch_name) do
    run(repo_path, ["checkout", branch_name])
  end

  def commit_all(repo_path, message) do
    with :ok <- run(repo_path, ["add", "-A"]),
         {:ok, status} <- status_porcelain(repo_path) do
      if status == [] do
        {:ok, :no_changes}
      else
        with :ok <- run(repo_path, ["commit", "-m", message]),
             {:ok, sha} <- rev_parse(repo_path, "HEAD") do
          {:ok, sha}
        end
      end
    end
  end

  def push_branch(repo_path, branch_name) do
    run(repo_path, ["push", "-u", "origin", "#{branch_name}:#{branch_name}"])
  end

  def rev_parse(repo_path, rev) do
    case cmd(repo_path, ["rev-parse", rev]) do
      {:ok, output} -> {:ok, String.trim(output)}
      {:error, reason} -> {:error, reason}
    end
  end

  def changed_files(repo_path) do
    with {:ok, status} <- status_porcelain(repo_path) do
      files =
        status
        |> Enum.map(&String.trim_leading(&1))
        |> Enum.map(fn line ->
          case String.split(line, ~r/\s+/, parts: 2) do
            [_status, path] -> path
            [path] -> path
          end
        end)
        |> Enum.uniq()

      {:ok, files}
    end
  end

  def merge_remote_branch(repo_path, branch_name) do
    run(repo_path, ["merge", "--no-ff", "--no-edit", "origin/#{branch_name}"])
  end

  def push_ref(repo_path, local_ref, remote_ref) do
    run(repo_path, ["push", "origin", "#{local_ref}:#{remote_ref}"])
  end

  defp status_porcelain(repo_path) do
    case cmd(repo_path, ["status", "--porcelain"]) do
      {:ok, output} ->
        {:ok, String.split(output, "\n", trim: true)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp run(repo_path, args) do
    case cmd(repo_path, args) do
      {:ok, _output} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp cmd(repo_path, args) do
    opts =
      [stderr_to_stdout: true]
      |> maybe_put_cd(repo_path)

    case System.cmd("git", args, opts) do
      {output, 0} -> {:ok, output}
      {output, _code} -> {:error, {:git_failed, args, output}}
    end
  end

  defp maybe_put_cd(opts, nil), do: opts
  defp maybe_put_cd(opts, repo_path), do: Keyword.put(opts, :cd, repo_path)
end
