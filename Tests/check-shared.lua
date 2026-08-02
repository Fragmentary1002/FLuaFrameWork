local registered = require("Tests.SharedTestBootstrap")
require("FLuaFramework.App.UI.Login.LoginPresenter")
require("FLuaFramework.Config.FPages")
require("FLuaFramework.Config.FLayers")
require("FLuaFramework.Config.FAssets")
require("FLuaFramework.Config.FLocales")

local count = 0
for _ in pairs(registered) do count = count + 1 end
print(string.format(
    "parsed %d shared framework modules and 5 config/app modules",
    count
))
