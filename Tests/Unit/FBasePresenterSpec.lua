local FTestHelper = require("Tests.TestHelper")
local FBasePresenter = require("FLuaFramework.Shared.Core.FBasePresenter")

FTestHelper:test("presenter unbind releases every tracked subscription once", function()
    local presenter = FBasePresenter:new()
    local first_calls = 0
    local second_calls = 0
    presenter:track({ unsubscribe = function() first_calls = first_calls + 1 end })
    presenter:track({ unsubscribe = function() second_calls = second_calls + 1 end })

    presenter:on_unbind()
    presenter:on_unbind()

    FTestHelper:assert_equal(1, first_calls)
    FTestHelper:assert_equal(1, second_calls)
end)

FTestHelper:test("presenter rejects invalid subscription handles", function()
    FTestHelper:assert_error_code("INVALID_SUBSCRIPTION", function()
        FBasePresenter:new():track({})
    end)
end)

FTestHelper:test("presenter unbind cancels tracked requests once", function()
    local presenter = FBasePresenter:new()
    local calls = 0
    presenter:track_request({ cancel = function() calls = calls + 1 end })
    presenter:on_unbind()
    presenter:on_unbind()
    FTestHelper:assert_equal(1, calls)
end)

FTestHelper:test("presenter unbind releases tracked resources once", function()
    local presenter = FBasePresenter:new()
    local calls = 0
    presenter:track_resource({ release = function() calls = calls + 1 end })
    presenter:on_unbind()
    presenter:on_unbind()
    FTestHelper:assert_equal(1, calls)
end)

FTestHelper:test("presenter rejects invalid request handles", function()
    FTestHelper:assert_error_code("INVALID_CANCELABLE", function()
        FBasePresenter:new():track_request({})
    end)
end)

FTestHelper:test("presenter rejects invalid resource handles", function()
    FTestHelper:assert_error_code("INVALID_RESOURCE", function()
        FBasePresenter:new():track_resource({})
    end)
end)

FTestHelper:test("presenter continues cleanup after one handle fails", function()
    local presenter = FBasePresenter:new()
    local released = 0
    presenter:track_resource({ release = function() released = released + 1 end })
    presenter:track_resource({ release = function() error("release failed") end })

    local succeeded, failure = pcall(function() presenter:on_unbind() end)

    FTestHelper:assert_false(succeeded)
    FTestHelper:assert_contains("release failed", failure)
    FTestHelper:assert_equal(1, released)
end)
