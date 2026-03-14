defmodule Forgelet.Repo do
  @moduledoc false

  use Ecto.Repo,
    otp_app: :forgelet,
    adapter: Ecto.Adapters.Postgres
end
