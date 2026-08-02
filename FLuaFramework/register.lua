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
register("FIWidget", "FLuaFramework.Shared.Contracts.FWidget.FIWidget")
register("FIText", "FLuaFramework.Shared.Contracts.FWidget.FIText")
register("FIButton", "FLuaFramework.Shared.Contracts.FWidget.FIButton")
register("FIImage", "FLuaFramework.Shared.Contracts.FWidget.FIImage")
register("FIInput", "FLuaFramework.Shared.Contracts.FWidget.FIInput")
register("FIToggle", "FLuaFramework.Shared.Contracts.FWidget.FIToggle")
register("FIProgress", "FLuaFramework.Shared.Contracts.FWidget.FIProgress")
register("FIView", "FLuaFramework.Shared.Contracts.FIView")
register("FAssetHandle", "FLuaFramework.Shared.Contracts.FAssetLoader.FAssetHandle")
register("FIAssetLoader", "FLuaFramework.Shared.Contracts.FAssetLoader.FIAssetLoader")
register("FILogger", "FLuaFramework.Shared.Contracts.FLogger.FILogger")
register("FILocalization", "FLuaFramework.Shared.Localization.FILocalization")
register("FEventBus", "FLuaFramework.Shared.Events.FEventBus")
register("FStore", "FLuaFramework.Shared.State.FStore")
register("FCommand", "FLuaFramework.Shared.Utils.FCommand")
register("FValidation", "FLuaFramework.Shared.Utils.FValidation")
register("FViewBinder", "FLuaFramework.Adapters.Common.FViewBinder")
register("FUIManager", "FLuaFramework.Shared.Core.FUIManager")
register("FUIRouter", "FLuaFramework.Shared.Core.FUIRouter")

-- Adapters
register("FUnrealRuntime", "FLuaFramework.Adapters.Unreal.FUnrealRuntime")
register("FUnityRuntime", "FLuaFramework.Adapters.Unity.FUnityRuntime")

return registered
