defmodule WorkersUniteWeb.PageController do
  @moduledoc "Handles requests for static pages such as the landing page."
  use WorkersUniteWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
