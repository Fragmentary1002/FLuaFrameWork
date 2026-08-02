local registered = require("FLuaFramework.register")
local pages = require("FLuaFramework.Config.FPages")

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

    return registered.FUIManager:new({
        runtime = runtime_class:new(options.bridge),
        pages = pages,
        services = options.services or {},
    })
end

return init
