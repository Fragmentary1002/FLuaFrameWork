local FTestHelper = require("Tests.TestHelper")
local FBasePresenter = require("LuaUIFramework.Shared.Core.FBasePresenter")

FTestHelper:test("presenter unbind releases every tracked subscription once", function()
    local presenter = FBasePresenter.new()
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
        FBasePresenter.new():track({})
    end)
end)
