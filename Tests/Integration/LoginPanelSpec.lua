local FTestHelper = require("Tests.TestHelper")
local FFakePlatformBridge = require("Tests.Fixtures.FFakePlatformBridge")
local FUnrealRuntime = require("FLuaFramework.Adapters.Unreal.FUnrealRuntime")
local FUnityRuntime = require("FLuaFramework.Adapters.Unity.FUnityRuntime")
local FUIManager = require("FLuaFramework.Shared.Core.FUIManager")
local pages = require("FLuaFramework.Config.FPages")
local layers = require("FLuaFramework.Config.FLayers")

local cases = {
    { platform = "unreal", runtime = FUnrealRuntime, bridge = "as_unreal" },
    { platform = "unity", runtime = FUnityRuntime, bridge = "as_unity" },
}

for _, case in ipairs(cases) do
    FTestHelper:test("LoginPresenter completes login on " .. case.platform, function()
        local fake = FFakePlatformBridge:new(case.platform)
        local service_calls = 0
        local manager = FUIManager:new({
            runtime = case.runtime:new(fake[case.bridge](fake)),
            pages = pages,
            layers = layers,
            services = { login = function(account)
                service_calls = service_calls + 1
                return account == "alice", account == "alice" and nil or "登录失败"
            end },
        })
        manager:open("LoginPanel", { account = "alice", avatar = "avatar/alice" })
        fake:complete_next()
        local instance = manager:get("LoginPanel")
        local native = instance.view.native
        FTestHelper:assert_equal("登录", native.widgets.title.text)
        FTestHelper:assert_equal("alice", native.widgets.account_text.text)
        FTestHelper:assert_equal("avatar/alice", native.widgets.avatar.source)

        native.widgets.login_button.click()
        FTestHelper:assert_equal(1, service_calls)
        FTestHelper:assert_equal("登录成功", native.widgets.status_text.text)

        manager:close("LoginPanel")
        FTestHelper:assert_nil(native.widgets.login_button.click)
    end)
end
