local FError = require("LuaUIFramework.Shared.Core.FError")
local FIText = require("LuaUIFramework.Shared.Contracts.FIText")
local FIButton = require("LuaUIFramework.Shared.Contracts.FIButton")
local FIImage = require("LuaUIFramework.Shared.Contracts.FIImage")
local FIView = require("LuaUIFramework.Shared.Contracts.FIView")

local FViewBinder = {}
local factories = {
    Text = function(...) return FIText:new(...) end,
    Button = function(...) return FIButton:new(...) end,
    Image = function(...) return FIImage:new(...) end,
}

function FViewBinder.bind(page, platform, native_view, required_bindings, bridge)
    local widgets = {}
    for id, expected in pairs(required_bindings) do
        local native_widget = bridge.resolve(native_view, id)
        if native_widget == nil then
            error(FError:new("BINDING_NOT_FOUND", "required view binding was not found", {
                page = page, platform = platform, binding = id, expected = expected,
            }), 0)
        end
        local actual = bridge.kind(native_widget)
        if actual ~= expected or factories[expected] == nil then
            error(FError:new("BINDING_TYPE_MISMATCH", "view binding type does not match", {
                page = page, platform = platform, binding = id, expected = expected, actual = actual,
            }), 0)
        end
        widgets[id] = {
            kind = actual,
            widget = factories[actual](id, native_widget, bridge.widget_ops(native_widget, actual)),
        }
    end
    return FIView:new(page, platform, native_view, bridge.view_ops(native_view), widgets)
end

return FViewBinder
