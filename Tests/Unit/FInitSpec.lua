local FTestHelper = require("Tests.TestHelper")
local FFakePlatformBridge = require("Tests.Fixtures.FFakePlatformBridge")
local init = require("init")

local cases = {
    { platform = "unreal", bridge = "as_unreal", runtime = FUnrealRuntime },
    { platform = "unity", bridge = "as_unity", runtime = FUnityRuntime },
}

for _, case in ipairs(cases) do
    FTestHelper:test("init creates a manager for " .. case.platform, function()
        local fake = FFakePlatformBridge:new(case.platform)
        local services = {}
        local manager = init.create({
            platform = case.platform,
            bridge = fake[case.bridge](fake),
            services = services,
        })

        FTestHelper:assert_true(case.runtime:is_instance(manager.runtime))
        FTestHelper:assert_equal(case.platform, manager.runtime.platform)
        FTestHelper:assert_equal(services, manager.services)
        FTestHelper:assert_not_nil(manager.pages.LoginPanel)
        FTestHelper:assert_not_nil(manager.router)
        FTestHelper:assert_not_nil(manager.asset_loader)
        FTestHelper:assert_not_nil(manager.logger)
        FTestHelper:assert_equal(case.platform, manager.logger.platform)
        FTestHelper:assert_not_nil(manager.layers.Normal)
    end)
end

FTestHelper:test("init rejects missing options", function()
    FTestHelper:assert_error_code("INVALID_ARGUMENT", function()
        init.create()
    end)
end)

FTestHelper:test("init rejects a missing bridge", function()
    FTestHelper:assert_error_code("INVALID_ARGUMENT", function()
        init.create({ platform = "unreal" })
    end)
end)

FTestHelper:test("init rejects a missing platform", function()
    FTestHelper:assert_error_code("INVALID_ARGUMENT", function()
        init.create({ bridge = {} })
    end)
end)

FTestHelper:test("init rejects an unsupported platform", function()
    FTestHelper:assert_error_code("UNSUPPORTED_PLATFORM", function()
        init.create({ platform = "unknown", bridge = {} })
    end)
end)
