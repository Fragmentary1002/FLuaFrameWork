local Class = require("LuaUIFramework.Shared.Core.FClass")
local FFakePlatformBridge = Class("FFakePlatformBridge")

function FFakePlatformBridge:ctor(platform)
    self.platform = platform
    self.pending = {}
    self.destroyed = 0
end

function FFakePlatformBridge:make_native_view()
    local widgets = {}
    local function add(id, kind)
        widgets[id] = { id = id, kind = kind, valid = true, visible = true, text = "", source = nil }
    end
    add("title", "Text")
    add("account_text", "Text")
    add("login_button", "Button")
    add("status_text", "Text")
    add("avatar", "Image")
    return { valid = true, visible = false, widgets = widgets }
end

function FFakePlatformBridge:_load(asset, callback)
    local request = { asset = asset, callback = callback, cancelled = false }
    table.insert(self.pending, request)
    return { cancel = function() request.cancelled = true end }
end

function FFakePlatformBridge:complete_next(deliver_cancelled)
    local request = table.remove(self.pending, 1)
    if request ~= nil and (not request.cancelled or deliver_cancelled == true) then
        request.callback(self:make_native_view())
    end
end

function FFakePlatformBridge:_resolve(root, id) return root.widgets[id] end
function FFakePlatformBridge:_kind(widget) return widget.kind end

function FFakePlatformBridge:_widget_ops(widget)
    return {
        is_valid = function() return widget.valid end,
        set_visible = function(value) widget.visible = value end,
        set_text = function(value) widget.text = value end,
        get_text = function() return widget.text end,
        on_click = function(callback)
            widget.click = callback
            local active = true
            return { unsubscribe = function()
                if active then active = false; widget.click = nil end
            end }
        end,
        set_source = function(source) widget.source = source end,
    }
end

function FFakePlatformBridge:_view_ops(root)
    return {
        is_valid = function() return root.valid end,
        set_visible = function(value) root.visible = value end,
        destroy = function()
            if root.valid then root.valid = false; self.destroyed = self.destroyed + 1 end
            for _, widget in pairs(root.widgets) do widget.valid = false; widget.click = nil end
        end,
    }
end

function FFakePlatformBridge:as_unreal()
    return {
        load_widget = function(asset, callback) return self:_load(asset, callback) end,
        find_widget = function(root, id) return self:_resolve(root, id) end,
        get_widget_type = function(widget) return self:_kind(widget) end,
        make_widget_ops = function(widget) return self:_widget_ops(widget) end,
        make_view_ops = function(root) return self:_view_ops(root) end,
        destroy_native_view = function(root) return self:_view_ops(root).destroy() end,
    }
end

function FFakePlatformBridge:as_unity()
    return {
        load_prefab = function(asset, callback) return self:_load(asset, callback) end,
        find_component = function(root, id) return self:_resolve(root, id) end,
        get_component_type = function(widget) return self:_kind(widget) end,
        make_component_ops = function(widget) return self:_widget_ops(widget) end,
        make_view_ops = function(root) return self:_view_ops(root) end,
        destroy_native_view = function(root) return self:_view_ops(root).destroy() end,
    }
end

return FFakePlatformBridge
