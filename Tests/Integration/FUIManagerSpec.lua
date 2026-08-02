local FTestHelper = require("Tests.TestHelper")
local Class = require("LuaUIFramework.Shared.Core.FClass")
local FFakePlatformBridge = require("Tests.Fixtures.FFakePlatformBridge")
local FUnrealRuntime = require("LuaUIFramework.Adapters.Unreal.FUnrealRuntime")
local FUIManager = require("LuaUIFramework.Shared.Core.FUIManager")

local function presenter_module(events)
    local FakePresenter = Class("FakePresenter")
    for _, name in ipairs({ "create", "bind", "open", "show", "hide", "close", "unbind", "destroy" }) do
        FakePresenter["on_" .. name] = function() table.insert(events, name) end
    end
    return FakePresenter
end

local function make_manager()
    local fake = FFakePlatformBridge:new("unreal")
    local events = {}
    local manager = FUIManager:new({
        runtime = FUnrealRuntime:new(fake:as_unreal()),
        pages = { LoginPanel = {
            presenter = "FakePresenter", singleton = true, cachePolicy = "DestroyOnClose",
            assets = { unreal = "WBP_LoginPanel" }, requiredBindings = {
                title = "Text", account_text = "Text", login_button = "Button",
                status_text = "Text", avatar = "Image",
            },
        } },
        require_module = function() return presenter_module(events) end,
    })
    return manager, fake, events
end

FTestHelper:test("manager opens a registered page in lifecycle order", function()
    local manager, fake, events = make_manager()
    manager:open("LoginPanel", { account = "alice" })
    FTestHelper:assert_equal("Loading", manager:get("LoginPanel").lifecycle:get_state())
    fake:complete_next()
    FTestHelper:assert_equal("Opened", manager:get("LoginPanel").lifecycle:get_state())
    FTestHelper:assert_equal("create,bind,open,show", table.concat(events, ","))
    FTestHelper:assert_true(manager:is_open("LoginPanel"))
end)

FTestHelper:test("manager hides and shows an opened page", function()
    local manager, fake, events = make_manager()
    manager:open("LoginPanel")
    fake:complete_next()
    local native = manager:get("LoginPanel").view.native
    FTestHelper:assert_true(manager:hide("LoginPanel"))
    FTestHelper:assert_equal("Hidden", manager:get("LoginPanel").lifecycle:get_state())
    FTestHelper:assert_false(native.visible)
    FTestHelper:assert_true(manager:show("LoginPanel"))
    FTestHelper:assert_equal("Opened", manager:get("LoginPanel").lifecycle:get_state())
    FTestHelper:assert_true(native.visible)
    FTestHelper:assert_equal("create,bind,open,show,hide,show", table.concat(events, ","))
end)

FTestHelper:test("closing an opened page unbinds before destroying", function()
    local manager, fake, events = make_manager()
    manager:open("LoginPanel")
    fake:complete_next()
    manager:close("LoginPanel", "done")
    FTestHelper:assert_nil(manager:get("LoginPanel"))
    FTestHelper:assert_equal("create,bind,open,show,hide,close,unbind,destroy", table.concat(events, ","))
    FTestHelper:assert_equal(1, fake.destroyed)
end)

FTestHelper:test("closing a loading page cancels and ignores a late callback", function()
    local manager, fake, events = make_manager()
    manager:open("LoginPanel")
    manager:close("LoginPanel")
    fake:complete_next(true)
    FTestHelper:assert_nil(manager:get("LoginPanel"))
    FTestHelper:assert_equal("", table.concat(events, ","))
end)

FTestHelper:test("manager rejects an unknown page with a unified error", function()
    local manager = make_manager()
    FTestHelper:assert_error_code("PAGE_NOT_REGISTERED", function() manager:open("MissingPanel") end)
end)

FTestHelper:test("binding failure removes the half-open page and destroys native view", function()
    local manager, fake = make_manager()
    manager.pages.LoginPanel.requiredBindings.missing = "Text"
    manager:open("LoginPanel")
    local succeeded, failure = pcall(function() fake:complete_next() end)
    FTestHelper:assert_false(succeeded)
    FTestHelper:assert_equal("BINDING_NOT_FOUND", failure.code)
    FTestHelper:assert_nil(manager:get("LoginPanel"))
end)
