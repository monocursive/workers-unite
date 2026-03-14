defmodule ForgeletWeb.ConsensusLiveTest do
  use ForgeletWeb.ConnCase

  import Phoenix.LiveViewTest

  setup :register_and_log_in_onboarded_user

  test "renders consensus view", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/consensus")

    assert html =~ "Consensus"
    assert html =~ "Active Proposals"
    assert html =~ "Completed Decisions"
  end
end
