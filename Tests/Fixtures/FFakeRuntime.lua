local FClass = require("FLuaFramework.Shared.Core.FClass")
local FMockView = require("Tests.Fixtures.FMockView")
local FFakeRuntime = FClass("FFakeRuntime")

function FFakeRuntime:ctor(platform)
    self.platform = platform
    self.pending = {}
    self.mounts = {}
    self.destroyed = 0
end

function FFakeRuntime:load_view(asset, callback)
    local pending = { asset = asset, callback = callback, cancelled = false }
    table.insert(self.pending, pending)
    return { cancel = function() pending.cancelled = true end }
end

function FFakeRuntime:complete_next(deliver_cancelled)
    local pending = table.remove(self.pending, 1)
    if pending ~= nil and (not pending.cancelled or deliver_cancelled == true) then
        pending.callback({ valid = true })
    end
end

function FFakeRuntime:mount_view(native_view, layer_name, layer, input_mode)
    table.insert(self.mounts, {
        native = native_view,
        layer = layer_name,
        order = layer.order,
        blocksInput = layer.blocksInput,
        inputMode = input_mode,
    })
end

function FFakeRuntime:bind_view(page, native_view, required_bindings)
    local mock = FMockView:new(required_bindings)
    native_view.mock = mock
    return mock.view
end

function FFakeRuntime:destroy_native_view(native_view)
    if native_view.valid then
        native_view.valid = false
        self.destroyed = self.destroyed + 1
    end
end

return FFakeRuntime
