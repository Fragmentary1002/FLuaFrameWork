local registered = require("FLuaFramework.register")
require("FLuaFramework.App.UI.Login.LoginPresenter")
require("FLuaFramework.Config.FPages")
require("init")
require("main")

local registered_count = 0
for _ in pairs(registered) do
    registered_count = registered_count + 1
end

print(string.format(
    "parsed %d registered framework modules, 2 app modules and 2 entry modules",
    registered_count
))
