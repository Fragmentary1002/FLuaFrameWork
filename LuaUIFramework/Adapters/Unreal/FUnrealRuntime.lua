local FViewBinder = require("LuaUIFramework.Adapters.Common.FViewBinder")
local FUnrealRuntime = {}
FUnrealRuntime.__index = FUnrealRuntime

function FUnrealRuntime.new(bridge)
    return setmetatable({ platform = "unreal", bridge = bridge }, FUnrealRuntime)
end

function FUnrealRuntime:load_view(asset, callback)
    return self.bridge.load_widget(asset, callback)
end

function FUnrealRuntime:bind_view(page, native_view, required_bindings)
    local bridge = self.bridge
    return FViewBinder.bind(page, self.platform, native_view, required_bindings, {
        resolve = bridge.find_widget,
        kind = bridge.get_widget_type,
        widget_ops = bridge.make_widget_ops,
        view_ops = bridge.make_view_ops,
    })
end

function FUnrealRuntime:destroy_native_view(native_view)
    self.bridge.destroy_native_view(native_view)
end

return FUnrealRuntime
