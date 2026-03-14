defmodule WorkersUnite.EventHelpers do
  @moduledoc """
  Shared helpers for generating valid test events.
  """

  alias WorkersUnite.{Event, Identity}

  def generate_keypair do
    Identity.generate()
  end

  def build_event(kind, opts \\ []) do
    keypair = Keyword.get(opts, :keypair, generate_keypair())
    payload = Keyword.get(opts, :payload, %{})
    event_opts = Keyword.get(opts, :event_opts, [])
    {:ok, event} = Event.new(kind, keypair, payload, event_opts)
    event
  end

  def build_intent_event(opts \\ []) do
    payload =
      Keyword.get(opts, :payload, %{
        "title" => "Test intent",
        "description" => "A test intent"
      })

    build_event(:intent_published, Keyword.put(opts, :payload, payload))
  end

  def build_proposal_event(intent_ref, opts \\ []) do
    payload =
      Keyword.get(opts, :payload, %{
        "intent_ref" => intent_ref,
        "repo_id" => Base.encode16(:crypto.strong_rand_bytes(16), case: :lower),
        "summary" => "Test proposal",
        "confidence" => 0.8,
        "affected_files" => ["lib/example.ex"],
        "artifact" => %{"type" => "commit_range", "from" => "abc123", "to" => "def456"}
      })

    build_event(:proposal_submitted, Keyword.put(opts, :payload, payload))
  end

  def build_vote_event(proposal_ref, verdict, opts \\ []) do
    payload =
      Keyword.get(opts, :payload, %{
        "proposal_ref" => proposal_ref,
        "verdict" => to_string(verdict)
      })

    build_event(:vote_cast, Keyword.put(opts, :payload, payload))
  end
end
