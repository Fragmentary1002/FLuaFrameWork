local Class = require("LuaUIFramework.Shared.Core.FClass")
local FViewBinder = require("LuaUIFramework.Adapters.Common.FViewBinder")
local FUnityRuntime = Class("FUnityRuntime")

function FUnityRuntime:ctor(bridge)
    self.platform = "unity"
    self.bridge = bridge
end

function FUnityRuntime:load_view(asset, callback)
    return self.bridge.load_prefab(asset, callback)
end

function FUnityRuntime:bind_view(page, native_view, required_bindings)
    local bridge = self.bridge
    return FViewBinder.bind(page, self.platform, native_view, required_bindings, {
        resolve = bridge.find_component,
        kind = bridge.get_component_type,
        widget_ops = bridge.make_component_ops,
        view_ops = bridge.make_view_ops,
    })
end

function FUnityRuntime:destroy_native_view(native_view)
    self.bridge.destroy_native_view(native_view)
end

return FUnityRuntime
