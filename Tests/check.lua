local registered = require("FLuaFramework.register")
require("FLuaFramework.App.UI.Login.LoginPresenter")
require("FLuaFramework.Config.FPages")

local registered_count = 0
for _ in pairs(registered) do
    registered_count = registered_count + 1
end

print(string.format("parsed %d registered framework modules and 2 app modules", registered_count))
