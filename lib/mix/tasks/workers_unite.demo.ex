defmodule Mix.Tasks.WorkersUnite.Demo do
  @moduledoc """
  Runs the WorkersUnite demo workflow.

  ## Usage

      mix workers_unite.demo
  """

  use Mix.Task

  @shortdoc "Runs the WorkersUnite collaboration demo"

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")
    WorkersUnite.Demo.run()
  end
end
