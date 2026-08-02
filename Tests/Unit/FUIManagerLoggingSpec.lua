local FTestHelper = require("Tests.TestHelper")
local FFakeRuntime = require("Tests.Fixtures.FFakeRuntime")

FTestHelper:test("manager logs synchronous page errors with platform context", function()
    local record = nil
    local logger = FILogger:new("test", function(value) record = value end)
    local manager = FUIManager:new({
        runtime = FFakeRuntime:new("test"), pages = {}, layers = {}, logger = logger,
    })
    FTestHelper:assert_error_code("PAGE_NOT_REGISTERED", function() manager:open("Missing") end)
    FTestHelper:assert_equal("PAGE_NOT_REGISTERED", record.errorCode)
    FTestHelper:assert_equal("Missing", record.page)
    FTestHelper:assert_equal("test", record.platform)
end)
