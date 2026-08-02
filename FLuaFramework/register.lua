local registered = {}

local function register(name, module_name)
    local module = require(module_name)
    registered[name] = module
    _G[name] = module
end

--Core
register("FClass", "FLuaFramework.Shared.Core.FClass")
register("FError", "FLuaFramework.Shared.Core.FError")
register("FBasePresenter", "FLuaFramework.Shared.Core.FBasePresenter")
register("FLifecycle", "FLuaFramework.Shared.Core.FLifecycle")
register("FIWidget", "FLuaFramework.Shared.Contracts.FIWidget")
register("FIText", "FLuaFramework.Shared.Contracts.FIText")
register("FIButton", "FLuaFramework.Shared.Contracts.FIButton")
register("FIImage", "FLuaFramework.Shared.Contracts.FIImage")
register("FIView", "FLuaFramework.Shared.Contracts.FIView")
register("FEventBus", "FLuaFramework.Shared.Events.FEventBus")
register("FStore", "FLuaFramework.Shared.State.FStore")
register("FCommand", "FLuaFramework.Shared.Utils.FCommand")
register("FValidation", "FLuaFramework.Shared.Utils.FValidation")
register("FViewBinder", "FLuaFramework.Adapters.Common.FViewBinder")
register("FUIManager", "FLuaFramework.Shared.Core.FUIManager")

-- Adapters
register("FUnrealRuntime", "FLuaFramework.Adapters.Unreal.FUnrealRuntime")
register("FUnityRuntime", "FLuaFramework.Adapters.Unity.FUnityRuntime")

return registered
