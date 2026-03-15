ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Journalex.Repo, :manual)

# Define Mox mocks for behaviours used in LiveView tests
Mox.defmock(Journalex.MockActivity, for: Journalex.ActivityBehaviour)
Mox.defmock(Journalex.MockTrades, for: Journalex.TradesBehaviour)
Mox.defmock(Journalex.MockSettings, for: Journalex.SettingsBehaviour)
Mox.defmock(Journalex.MockParser, for: Journalex.ParserBehaviour)
Mox.defmock(Journalex.MockWriteupDrafts, for: Journalex.WriteupDraftsBehaviour)
