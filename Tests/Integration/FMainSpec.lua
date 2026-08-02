local FTestHelper = require("Tests.TestHelper")
local FFakePlatformBridge = require("Tests.Fixtures.FFakePlatformBridge")
local main = require("main")

FTestHelper:test("main starts and opens LoginPanel", function()
    local fake = FFakePlatformBridge:new("unreal")
    local params = { account = "alice", avatar = "avatar/alice" }
    local manager = main.start({
        platform = "unreal",
        bridge = fake:as_unreal(),
        services = {},
        params = params,
    })

    local instance = manager:get("LoginPanel")
    FTestHelper:assert_not_nil(instance)
    FTestHelper:assert_equal("Loading", instance.lifecycle:get_state())
    FTestHelper:assert_equal(params, instance.params)
    FTestHelper:assert_equal("/Game/UI/Login/WBP_LoginPanel", fake.pending[1].asset)
end)
