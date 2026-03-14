defmodule Forgelet.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ForgeletWeb.Telemetry,
      Forgelet.Repo,
      {DNSCluster, query: Application.get_env(:forgelet, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Forgelet.PubSub},
      Forgelet.Identity.Vault,
      Forgelet.CredentialStore,
      Forgelet.EventStore,
      Forgelet.Control.NodeRegistry,
      Forgelet.Control.JobRegistry,
      Forgelet.Control.NodeManager,
      Forgelet.Control.JobScheduler,
      Forgelet.Control.WorkflowEngine,
      Forgelet.Control.Reporter,
      Forgelet.Control.Master,
      Forgelet.Agent.SessionRegistry,
      {Horde.Registry, name: Forgelet.Registry, keys: :unique, members: :auto},
      {Horde.DynamicSupervisor,
       name: Forgelet.AgentSupervisor, strategy: :one_for_one, members: :auto},
      {Horde.DynamicSupervisor,
       name: Forgelet.RepoSupervisor, strategy: :one_for_one, members: :auto},
      {DynamicSupervisor, name: Forgelet.SessionSupervisor, strategy: :one_for_one},
      Forgelet.Consensus.Engine,
      ForgeletWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Forgelet.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    ForgeletWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
