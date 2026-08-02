local FTestHelper = require("Tests.TestHelper")
local FILogger = require("FLuaFramework.Shared.Contracts.FLogger.FILogger")

FTestHelper:test("logger merges platform base and call context", function()
    local record = nil
    local logger = FILogger:new("unreal", function(value) record = value end, {
        page = "LoginPanel", instanceId = 7,
    })
    logger:info("page opened", { lifecycle = "Opened" })
    FTestHelper:assert_equal("info", record.level)
    FTestHelper:assert_equal("unreal", record.platform)
    FTestHelper:assert_equal("LoginPanel", record.page)
    FTestHelper:assert_equal("Opened", record.lifecycle)
end)

FTestHelper:test("logger flattens FError context and records traceback", function()
    local record = nil
    local logger = FILogger:new("unity", function(value) record = value end)
    logger:error(FError:new("BINDING_NOT_FOUND", "missing", { binding = "title" }))
    FTestHelper:assert_equal("BINDING_NOT_FOUND", record.errorCode)
    FTestHelper:assert_equal("title", record.binding)
    FTestHelper:assert_contains("stack traceback", record.traceback)
end)
