defmodule JournalexWeb.Router do
  use JournalexWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {JournalexWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", JournalexWeb do
    pipe_through :browser

    get "/", PageController, :home
    # Live pages
    live "/activity_statement/upload/result", ActivityStatementUploadResultLive
    live "/activity_statement/dates", ActivityStatementDatesLive
    live "/activity_statement/upload", ActivityStatementUploadLive

    # Statement dump page
    live "/statement/dump", StatementDumpLive

    # Aggregated trades page
    live "/trade/all", TradesLive
    # Trades by date range
    live "/trade/dates", TradesDatesLive
    # Trades dump page
    live "/trade/dump", TradesDumpLive

    # Metadata drafts management page
    live "/trade/drafts", MetadataDraftLive

    # Settings page
    live "/settings", SettingsLive

    # Saved statements pages
    get "/activity_statement/all", ActivityStatementController, :index
    get "/activity_statement/:id", ActivityStatementController, :show
  end

  # Other scopes may use custom stacks.
  # scope "/api", JournalexWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:journalex, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: JournalexWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
