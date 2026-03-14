defmodule ForgeletWeb.HealthController do
  use ForgeletWeb, :controller

  def show(conn, _params) do
    json(conn, %{status: "ok"})
  end
end
