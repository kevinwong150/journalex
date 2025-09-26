defmodule JournalexWeb.ActivityStatementController do
  use JournalexWeb, :controller
  alias Journalex.Activity

  def index(conn, _params) do
    statements = Activity.list_activity_statements(limit: 500)
    render(conn, :index, statements: statements)
  end

  def show(conn, %{"id" => id}) do
    case Activity.get_activity_statement(id) do
      nil ->
        conn
        |> put_flash(:error, "Activity statement not found")
        |> redirect(to: ~p"/activity_statement/all")

      stmt ->
        render(conn, :show, statement: stmt)
    end
  end
end
