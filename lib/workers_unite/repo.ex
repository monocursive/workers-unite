defmodule WorkersUnite.Repo do
  @moduledoc false

  use Ecto.Repo,
    otp_app: :workers_unite,
    adapter: Ecto.Adapters.Postgres
end
