local FTestHelper = require("Tests.TestHelper")
local FMockView = require("Tests.Fixtures.FMockView")

local function make_mock()
    return FMockView:new({
        account_input = "Input",
        remember_toggle = "Toggle",
        loading_progress = "Progress",
    })
end

FTestHelper:test("input normalizes nil and releases changed callbacks", function()
    local mock = make_mock()
    local received = nil
    local handle = mock.view:input("account_input"):on_changed(function(value) received = value end)
    mock.view:input("account_input"):set_text(nil)
    FTestHelper:assert_equal("", mock.view:input("account_input"):get_text())
    mock:change("account_input", "alice")
    FTestHelper:assert_equal("alice", received)
    handle:unsubscribe()
    FTestHelper:assert_nil(mock:get("account_input").changed)
end)

FTestHelper:test("toggle exposes strict boolean state and changed callbacks", function()
    local mock = make_mock()
    local received = nil
    mock.view:toggle("remember_toggle"):on_changed(function(value) received = value end)
    mock.view:toggle("remember_toggle"):set_checked(1)
    FTestHelper:assert_false(mock.view:toggle("remember_toggle"):is_checked())
    mock:change("remember_toggle", true)
    FTestHelper:assert_true(received)
end)

FTestHelper:test("progress accepts only normalized numeric values", function()
    local mock = make_mock()
    mock.view:progress("loading_progress"):set_value(0.75)
    FTestHelper:assert_equal(0.75, mock.view:progress("loading_progress"):get_value())
    FTestHelper:assert_error_code("INVALID_PROGRESS_VALUE", function()
        mock.view:progress("loading_progress"):set_value(2)
    end)
    FTestHelper:assert_error_code("INVALID_PROGRESS_VALUE", function()
        mock.view:progress("loading_progress"):set_value("0.5")
    end)
end)
