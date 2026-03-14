defmodule WorkersUniteWeb.HealthController do
  use WorkersUniteWeb, :controller

  def show(conn, _params) do
    json(conn, %{status: "ok"})
  end
end
