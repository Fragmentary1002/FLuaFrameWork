require("Tests.SharedTestBootstrap")
local FTestHelper = require("Tests.TestHelper")

local specs = {
    "Tests/Unit/FEventBusSpec.lua",
    "Tests/Unit/FStoreSpec.lua",
    "Tests/Unit/FClassSpec.lua",
    "Tests/Unit/FLifecycleSpec.lua",
    "Tests/Unit/FBasePresenterSpec.lua",
    "Tests/Unit/LoginPresenterSpec.lua",
    "Tests/Unit/FCommonControlsSpec.lua",
    "Tests/Unit/FUILayerSpec.lua",
    "Tests/Unit/FUIRouterSpec.lua",
    "Tests/Unit/FUIRouterAsyncSpec.lua",
    "Tests/Unit/FUIStateRecoverySpec.lua",
    "Tests/Unit/FIAssetLoaderSpec.lua",
    "Tests/Unit/FILoggerSpec.lua",
    "Tests/Unit/FILocalizationSpec.lua",
    "Tests/Unit/FUIManagerLoggingSpec.lua",
}

for _, spec_path in ipairs(specs) do dofile(spec_path) end

local passed = 0
local failed = 0
for _, case in ipairs(FTestHelper.tests) do
    local succeeded, failure = pcall(case.body)
    if succeeded then
        passed = passed + 1
        print("PASS " .. case.name)
    else
        failed = failed + 1
        print("FAIL " .. case.name)
        print("  " .. tostring(failure))
    end
end

print(string.format("\n%d shared passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
