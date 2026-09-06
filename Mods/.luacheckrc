-- Mods run inside Synchrony's Lua environment, which injects globals that
-- luacheck otherwise can't see: `event` for registering handlers, and other
-- API tables documented in DocDownloader's rendered docs.
std = "luajit"
read_globals = {
	"event",
}
