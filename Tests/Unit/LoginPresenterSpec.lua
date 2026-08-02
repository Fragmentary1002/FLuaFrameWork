local FTestHelper = require("Tests.TestHelper")
local FMockView = require("Tests.Fixtures.FMockView")
local LoginPresenter = require("FLuaFramework.App.UI.Login.LoginPresenter")

local bindings = {
    title = "Text",
    account_text = "Text",
    login_button = "Button",
    status_text = "Text",
    avatar = "Image",
}

FTestHelper:test("LoginPresenter renders and submits through a mock view", function()
    local mock = FMockView:new(bindings)
    local calls = 0
    local presenter = LoginPresenter:new({ login = function(account)
        calls = calls + 1
        return account == "alice"
    end })
    presenter:on_create(mock.view, { account = "alice", avatar = "avatar/alice" })
    presenter:on_bind()
    presenter:on_open({ account = "alice", avatar = "avatar/alice" })
    FTestHelper:assert_equal("登录", mock:get("title").text)
    FTestHelper:assert_equal("alice", mock:get("account_text").text)
    FTestHelper:assert_equal("avatar/alice", mock:get("avatar").source)
    mock:click("login_button")
    FTestHelper:assert_equal(1, calls)
    FTestHelper:assert_equal("登录成功", mock:get("status_text").text)
end)

FTestHelper:test("LoginPresenter unbind removes mock button callbacks", function()
    local mock = FMockView:new(bindings)
    local presenter = LoginPresenter:new({ login = function() return true end })
    presenter:on_create(mock.view, {})
    presenter:on_bind()
    presenter:on_unbind()
    FTestHelper:assert_nil(mock:get("login_button").click)
end)
