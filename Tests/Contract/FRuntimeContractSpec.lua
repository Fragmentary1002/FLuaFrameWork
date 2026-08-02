local FTestHelper = require("Tests.TestHelper")
local FFakePlatformBridge = require("Tests.Fixtures.FFakePlatformBridge")
local FUnrealRuntime = require("LuaUIFramework.Adapters.Unreal.FUnrealRuntime")
local FUnityRuntime = require("LuaUIFramework.Adapters.Unity.FUnityRuntime")

local cases = {
    { platform = "unreal", runtime = FUnrealRuntime, bridge = "as_unreal" },
    { platform = "unity", runtime = FUnityRuntime, bridge = "as_unity" },
}

for _, case in ipairs(cases) do
    FTestHelper:test(case.platform .. " runtime loads and binds the same view contract", function()
        local fake = FFakePlatformBridge.new(case.platform)
        local runtime = case.runtime.new(fake[case.bridge](fake))
        local received = nil
        local request = runtime:load_view("asset/login", function(native) received = native end)
        FTestHelper:assert_not_nil(request.cancel)
        fake:complete_next()
        local view = runtime:bind_view("LoginPanel", received, {
            title = "Text", login_button = "Button", avatar = "Image",
        })
        view:text("title"):set_text("Login")
        view:image("avatar"):set_source("avatar/default")
        FTestHelper:assert_equal("Login", received.widgets.title.text)
        FTestHelper:assert_equal("avatar/default", received.widgets.avatar.source)
    end)
end
