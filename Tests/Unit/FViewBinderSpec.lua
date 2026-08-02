local FTestHelper = require("Tests.TestHelper")
local FViewBinder = require("LuaUIFramework.Adapters.Common.FViewBinder")

local function make_bridge(bindings)
    return {
        resolve = function(_, id) return bindings[id] end,
        kind = function(widget) return widget.kind end,
        widget_ops = function(widget)
            return {
                is_valid = function() return widget.valid end,
                set_visible = function(value) widget.visible = value end,
                set_text = function(value) widget.text = value end,
                get_text = function() return widget.text end,
                on_click = function(callback)
                    widget.click = callback
                    return { unsubscribe = function() widget.click = nil end }
                end,
                set_source = function(value) widget.source = value end,
            }
        end,
        view_ops = function(root)
            return {
                is_valid = function() return root.valid end,
                set_visible = function(value) root.visible = value end,
                destroy = function() root.valid = false end,
            }
        end,
    }
end

FTestHelper:test("view binder reports a missing binding with diagnostics", function()
    local bridge = make_bridge({})
    local succeeded, failure = pcall(function()
        FViewBinder.bind("LoginPanel", "unreal", { valid = true }, { title = "Text" }, bridge)
    end)
    FTestHelper:assert_false(succeeded)
    FTestHelper:assert_equal("BINDING_NOT_FOUND", failure.code)
    FTestHelper:assert_equal("LoginPanel", failure.context.page)
    FTestHelper:assert_equal("unreal", failure.context.platform)
    FTestHelper:assert_equal("title", failure.context.binding)
end)

FTestHelper:test("view binder rejects a binding type mismatch", function()
    local bridge = make_bridge({ title = { kind = "Button", valid = true } })
    local succeeded, failure = pcall(function()
        FViewBinder.bind("LoginPanel", "unity", { valid = true }, { title = "Text" }, bridge)
    end)
    FTestHelper:assert_false(succeeded)
    FTestHelper:assert_equal("BINDING_TYPE_MISMATCH", failure.code)
    FTestHelper:assert_equal("Text", failure.context.expected)
    FTestHelper:assert_equal("Button", failure.context.actual)
end)

FTestHelper:test("view exposes typed widgets and rejects access after destroy", function()
    local title = { kind = "Text", valid = true, text = "" }
    local button = { kind = "Button", valid = true }
    local avatar = { kind = "Image", valid = true }
    local root = { valid = true }
    local view = FViewBinder.bind("LoginPanel", "unreal", root, {
        title = "Text", login_button = "Button", avatar = "Image",
    }, make_bridge({ title = title, login_button = button, avatar = avatar }))

    view:text("title"):set_text("登录")
    view:image("avatar"):set_source("avatar/default")
    local calls = 0
    local subscription = view:button("login_button"):on_click(function() calls = calls + 1 end)
    button.click()
    subscription:unsubscribe()
    FTestHelper:assert_equal("登录", title.text)
    FTestHelper:assert_equal("avatar/default", avatar.source)
    FTestHelper:assert_equal(1, calls)

    view:destroy()
    FTestHelper:assert_error_code("NATIVE_OBJECT_INVALID", function() view:text("title") end)
end)
