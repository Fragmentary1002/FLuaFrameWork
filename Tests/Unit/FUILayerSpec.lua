local FTestHelper = require("Tests.TestHelper")
local FFakeRuntime = require("Tests.Fixtures.FFakeRuntime")
local FUIManager = require("FLuaFramework.Shared.Core.FUIManager")

local function presenter_module()
    local Presenter = FClass("LayerPresenter", FBasePresenter)
    return Presenter
end

local function make_manager()
    local runtime = FFakeRuntime:new("test")
    local manager = FUIManager:new({
        runtime = runtime,
        layers = {
            Normal = { order = 200, blocksInput = false },
            Modal = { order = 400, blocksInput = true },
        },
        pages = {
            MainPanel = {
                presenter = "LayerPresenter", singleton = true,
                layer = "Normal", inputMode = "UIOnly",
                assets = { test = "main" }, requiredBindings = {},
            },
            ConfirmDialog = {
                presenter = "LayerPresenter", singleton = true,
                layer = "Modal", inputMode = "UIOnly",
                assets = { test = "confirm" }, requiredBindings = {},
            },
        },
        require_module = function() return presenter_module() end,
    })
    return manager, runtime
end

FTestHelper:test("manager records layer metadata and delegates optional mounting", function()
    local manager, runtime = make_manager()
    manager:open("MainPanel")
    runtime:complete_next()
    local instance = manager:get("MainPanel")
    FTestHelper:assert_equal("Normal", instance.layer)
    FTestHelper:assert_equal("Normal", runtime.mounts[1].layer)
    FTestHelper:assert_equal(200, runtime.mounts[1].order)
    FTestHelper:assert_false(runtime.mounts[1].blocksInput)
end)

FTestHelper:test("manager rejects an unknown logical layer before loading", function()
    local manager, runtime = make_manager()
    manager.pages.MainPanel.layer = "Missing"
    FTestHelper:assert_error_code("LAYER_NOT_FOUND", function() manager:open("MainPanel") end)
    FTestHelper:assert_equal(0, #runtime.pending)
end)

FTestHelper:test("close_layer closes only matching instances", function()
    local manager, runtime = make_manager()
    manager:open("MainPanel")
    runtime:complete_next()
    manager:open("ConfirmDialog")
    runtime:complete_next()
    FTestHelper:assert_equal(1, manager:close_layer("Modal"))
    FTestHelper:assert_not_nil(manager:get("MainPanel"))
    FTestHelper:assert_nil(manager:get("ConfirmDialog"))
end)

FTestHelper:test("manager applies hide requested while page is loading", function()
    local manager, runtime = make_manager()
    manager:open("MainPanel")
    FTestHelper:assert_true(manager:hide("MainPanel"))
    runtime:complete_next()

    local instance = manager:get("MainPanel")
    FTestHelper:assert_equal("Hidden", instance.lifecycle:get_state())
    FTestHelper:assert_false(instance.view.native.visible)
    FTestHelper:assert_true(manager:show("MainPanel"))
    FTestHelper:assert_equal("Opened", instance.lifecycle:get_state())
end)
