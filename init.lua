local registered = require("FLuaFramework.register")
local pages = require("FLuaFramework.Config.FPages")
local layers = require("FLuaFramework.Config.FLayers")
local assets = require("FLuaFramework.Config.FAssets")

local init = {}

local runtimes = {
    unreal = registered.FUnrealRuntime,
    unity = registered.FUnityRuntime,
}

local function raise(code, message, context)
    error(registered.FError:new(code, message, context), 0)
end

function init.create(options)
    if type(options) ~= "table" then
        raise("INVALID_ARGUMENT", "options must be a table", { argument = "options" })
    end
    if options.bridge == nil then
        raise("INVALID_ARGUMENT", "bridge is required", { argument = "bridge" })
    end
    if options.platform == nil then
        raise("INVALID_ARGUMENT", "platform is required", { argument = "platform" })
    end

    local runtime_class = runtimes[options.platform]
    if runtime_class == nil then
        raise("UNSUPPORTED_PLATFORM", "platform is not supported", {
            platform = options.platform,
        })
    end

    local runtime = runtime_class:new(options.bridge)
    local logger = registered.FILogger:new(options.platform, options.log_sink)
    local manager = registered.FUIManager:new({
        runtime = runtime,
        pages = pages,
        layers = layers,
        services = options.services or {},
        logger = logger,
    })
    manager.router = registered.FUIRouter:new(manager)
    manager.asset_loader = registered.FIAssetLoader:new(
        options.platform,
        assets,
        options.asset_backend,
        logger
    )
    return manager
end

return init
