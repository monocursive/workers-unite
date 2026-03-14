defmodule WorkersUnite.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      WorkersUniteWeb.Telemetry,
      WorkersUnite.Repo,
      {DNSCluster, query: Application.get_env(:workers_unite, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: WorkersUnite.PubSub},
      WorkersUnite.Identity.Vault,
      WorkersUnite.CredentialStore,
      WorkersUnite.EventStore,
      WorkersUnite.Control.NodeRegistry,
      WorkersUnite.Control.JobRegistry,
      WorkersUnite.Control.NodeManager,
      WorkersUnite.Control.JobScheduler,
      WorkersUnite.Control.WorkflowEngine,
      WorkersUnite.Control.Reporter,
      WorkersUnite.Control.Master,
      WorkersUnite.Agent.SessionRegistry,
      {Horde.Registry, name: WorkersUnite.Registry, keys: :unique, members: :auto},
      {Horde.DynamicSupervisor,
       name: WorkersUnite.AgentSupervisor, strategy: :one_for_one, members: :auto},
      {Horde.DynamicSupervisor,
       name: WorkersUnite.RepoSupervisor, strategy: :one_for_one, members: :auto},
      {DynamicSupervisor, name: WorkersUnite.SessionSupervisor, strategy: :one_for_one},
      WorkersUnite.Consensus.Engine,
      WorkersUniteWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: WorkersUnite.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    WorkersUniteWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
