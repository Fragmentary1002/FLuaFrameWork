local registered = {}

local function register(name, module_name)
    local module = require(module_name)
    registered[name] = module
    _G[name] = module
end

register("FClass", "LuaUIFramework.Shared.Core.FClass")
register("FError", "LuaUIFramework.Shared.Core.FError")
register("FBasePresenter", "LuaUIFramework.Shared.Core.FBasePresenter")
register("FLifecycle", "LuaUIFramework.Shared.Core.FLifecycle")
register("FIWidget", "LuaUIFramework.Shared.Contracts.FIWidget")
register("FIText", "LuaUIFramework.Shared.Contracts.FIText")
register("FIButton", "LuaUIFramework.Shared.Contracts.FIButton")
register("FIImage", "LuaUIFramework.Shared.Contracts.FIImage")
register("FIView", "LuaUIFramework.Shared.Contracts.FIView")
register("FEventBus", "LuaUIFramework.Shared.Events.FEventBus")
register("FStore", "LuaUIFramework.Shared.State.FStore")
register("FCommand", "LuaUIFramework.Shared.Utils.FCommand")
register("FValidation", "LuaUIFramework.Shared.Utils.FValidation")
register("FViewBinder", "LuaUIFramework.Adapters.Common.FViewBinder")
register("FUIManager", "LuaUIFramework.Shared.Core.FUIManager")
register("FUnrealRuntime", "LuaUIFramework.Adapters.Unreal.FUnrealRuntime")
register("FUnityRuntime", "LuaUIFramework.Adapters.Unity.FUnityRuntime")

return registered
