defmodule Forgelet.Identity.Vault do
  @moduledoc """
  GenServer that manages a persistent Ed25519 keypair for node identity.
  Generates a new keypair on first boot and persists it to disk.
  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Client API
  # ---------------------------------------------------------------------------

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)

    key_path =
      Keyword.get(opts, :key_path, Application.app_dir(:forgelet, "priv/identity/node.key"))

    GenServer.start_link(__MODULE__, %{key_path: key_path}, name: name)
  end

  @doc "Returns the 32-byte Ed25519 public key."
  def public_key(server \\ __MODULE__) do
    GenServer.call(server, :public_key)
  end

  @doc "Signs `data` with the node's secret key."
  def sign(data, server \\ __MODULE__) do
    GenServer.call(server, {:sign, data})
  end

  @doc "Returns the 16-character hex fingerprint of the node's public key."
  def fingerprint(server \\ __MODULE__) do
    GenServer.call(server, :fingerprint)
  end

  # ---------------------------------------------------------------------------
  # Server callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(%{key_path: key_path}) do
    keypair =
      if File.exists?(key_path) do
        File.read!(key_path) |> :erlang.binary_to_term()
      else
        kp = Forgelet.Identity.generate()
        key_path |> Path.dirname() |> File.mkdir_p!()
        File.write!(key_path, :erlang.term_to_binary(kp))
        kp
      end

    {:ok, %{keypair: keypair, key_path: key_path}}
  end

  @impl true
  def handle_call(:public_key, _from, %{keypair: %{public: pub}} = state) do
    {:reply, pub, state}
  end

  @impl true
  def handle_call({:sign, data}, _from, %{keypair: %{secret: sec}} = state) do
    {:reply, Forgelet.Identity.sign(data, sec), state}
  end

  @impl true
  def handle_call(:fingerprint, _from, %{keypair: %{public: pub}} = state) do
    {:reply, Forgelet.Identity.fingerprint(pub), state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}
end
