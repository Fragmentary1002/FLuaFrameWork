local FTestHelper = {
    tests = {},
}

function FTestHelper:test(name, body)
    table.insert(self.tests, {
        name = name,
        body = body,
    })
end

function FTestHelper:assert_equal(expected, actual)
    if expected ~= actual then
        error(string.format("expected %s, got %s", tostring(expected), tostring(actual)), 2)
    end
end

function FTestHelper:assert_true(value)
    if value ~= true then
        error(string.format("expected true, got %s", tostring(value)), 2)
    end
end

function FTestHelper:assert_false(value)
    if value ~= false then
        error(string.format("expected false, got %s", tostring(value)), 2)
    end
end

function FTestHelper:assert_nil(value)
    if value ~= nil then
        error(string.format("expected nil, got %s", tostring(value)), 2)
    end
end

function FTestHelper:assert_not_nil(value)
    if value == nil then
        error("expected a non-nil value", 2)
    end
end

function FTestHelper:assert_contains(expected_fragment, actual)
    local text = tostring(actual)
    if string.find(text, expected_fragment, 1, true) == nil then
        error(string.format("expected %s to contain %s", text, expected_fragment), 2)
    end
end

function FTestHelper:assert_error_code(expected_code, body)
    local succeeded, result = pcall(body)
    if succeeded then
        error(string.format("expected error code %s, but no error was raised", expected_code), 2)
    end
    if type(result) ~= "table" or result.code ~= expected_code then
        local actual_code = type(result) == "table" and result.code or tostring(result)
        error(string.format("expected error code %s, got %s", expected_code, tostring(actual_code)), 2)
    end
end

return FTestHelper
