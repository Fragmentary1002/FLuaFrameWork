local FTestHelper = require("Tests.TestHelper")
local FILocalization = require("FLuaFramework.Shared.Localization.FILocalization")

local function make_localization()
    local logs = {}
    local logger = {
        warn = function(_, message, context)
            table.insert(logs, { message = message, context = context })
        end,
    }
    local localization = FILocalization:new({
        locale = "zh-CN",
        fallback = "en-US",
        catalogs = {
            ["zh-CN"] = { greeting = "你好，{name}", only_zh = "仅中文" },
            ["en-US"] = { greeting = "Hello, {name}", fallback_key = "Fallback" },
        },
        logger = logger,
    })
    return localization, logs
end

FTestHelper:test("localization translates and interpolates current locale", function()
    local localization = make_localization()
    FTestHelper:assert_equal("你好，Alice", localization:t("greeting", { name = "Alice" }))
end)

FTestHelper:test("localization falls back to configured locale", function()
    local localization = make_localization()
    FTestHelper:assert_equal("Fallback", localization:t("fallback_key"))
end)

FTestHelper:test("localization returns a visible marker and logs a missing key", function()
    local localization, logs = make_localization()
    FTestHelper:assert_equal("[missing]", localization:t("missing"))
    FTestHelper:assert_equal("missing", logs[1].context.key)
    FTestHelper:assert_equal("zh-CN", logs[1].context.locale)
end)

FTestHelper:test("localization notifies locale changes and unsubscribe is idempotent", function()
    local localization = make_localization()
    local received = {}
    local subscription = localization:on_locale_changed(function(locale)
        table.insert(received, locale)
    end)
    localization:set_locale("en-US")
    subscription:unsubscribe()
    subscription:unsubscribe()
    localization:set_locale("zh-CN")
    FTestHelper:assert_equal("en-US", received[1])
    FTestHelper:assert_equal(1, #received)
end)

FTestHelper:test("localization rejects an unknown locale", function()
    local localization = make_localization()
    FTestHelper:assert_error_code("LOCALE_NOT_REGISTERED", function()
        localization:set_locale("ja-JP")
    end)
end)

FTestHelper:test("localization rejects missing interpolation parameters", function()
    local localization = make_localization()
    FTestHelper:assert_error_code("LOCALIZATION_PARAM_MISSING", function()
        localization:t("greeting", {})
    end)
end)
