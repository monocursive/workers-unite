defmodule WorkersUniteWeb.UserRegistrationController do
  @moduledoc "Redirects /users/register to /onboarding. Registration is handled exclusively through onboarding."
  use WorkersUniteWeb, :controller

  def new(conn, _params) do
    conn |> redirect(to: ~p"/onboarding")
  end

  def create(conn, _params) do
    conn |> redirect(to: ~p"/onboarding")
  end
end
