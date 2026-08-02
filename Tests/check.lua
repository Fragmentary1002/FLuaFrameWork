local modules = {
    "LuaUIFramework.Shared.Core.FError",
    "LuaUIFramework.Shared.Core.FBasePresenter",
    "LuaUIFramework.Shared.Core.FLifecycle",
    "LuaUIFramework.Shared.Core.FUIManager",
    "LuaUIFramework.Shared.Contracts.FIWidget",
    "LuaUIFramework.Shared.Contracts.FIText",
    "LuaUIFramework.Shared.Contracts.FIButton",
    "LuaUIFramework.Shared.Contracts.FIImage",
    "LuaUIFramework.Shared.Contracts.FIView",
    "LuaUIFramework.Shared.Events.FEventBus",
    "LuaUIFramework.Shared.State.FStore",
    "LuaUIFramework.Shared.Utils.FCommand",
    "LuaUIFramework.Shared.Utils.FValidation",
    "LuaUIFramework.Adapters.Common.FViewBinder",
    "LuaUIFramework.Adapters.Unreal.FUnrealRuntime",
    "LuaUIFramework.Adapters.Unity.FUnityRuntime",
    "LuaUIFramework.App.UI.Login.LoginPresenter",
    "LuaUIFramework.Config.FPages",
}

for _, module_name in ipairs(modules) do
    require(module_name)
end

print(string.format("parsed %d Lua modules", #modules))
