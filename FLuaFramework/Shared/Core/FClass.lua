local FClass = {}
local class_info = setmetatable({}, { __mode = "k" })
local instance_info = setmetatable({}, { __mode = "k" })
local class_methods = {}
local object_methods = {}

local function raise(code, message, context)
    error(FError:new(code, message, context or {}), 0)
end

local function assert_class(value, code)
    local info = class_info[value]
    if info == nil then
        raise(code or "INVALID_CLASS", "value is not a class created by FClass", {
            class = tostring(value),
        })
    end
    return info
end

local function is_subclass_of(class, target)
    local current = class
    while current ~= nil do
        if current == target then
            return true
        end
        current = class_info[current].base
    end
    return false
end

local function find_instance_member(class, key)
    local current = class
    while current ~= nil do
        local value = rawget(current, key)
        if value ~= nil then
            return value
        end
        current = class_info[current].base
    end
    return nil
end

local function instance_index(instance, key)
    local info = instance_info[instance]
    if not info.destroyed then
        local member = find_instance_member(info.class, key)
        if member ~= nil then
            return member
        end
    end

    local method = object_methods[key]
    if method ~= nil then
        return method
    end
    if info.destroyed then
        raise("OBJECT_DESTROYED", "cannot access a method on a destroyed object", {
            class = class_info[info.class].name,
            member = key,
        })
    end
    return nil
end

local function instance_tostring(instance)
    local info = instance_info[instance]
    local handler = find_instance_member(info.class, "__tostring")
    if type(handler) == "function" then
        return handler(instance)
    end
    return "<" .. class_info[info.class].name .. ">"
end

local instance_metatable = {
    __index = instance_index,
    __tostring = instance_tostring,
}

function class_methods:new(...)
    assert_class(self)
    local instance = setmetatable({}, instance_metatable)
    instance_info[instance] = { class = self, destroyed = false }

    local chain = {}
    local current = self
    while current ~= nil do
        table.insert(chain, 1, current)
        current = class_info[current].base
    end
    for _, class in ipairs(chain) do
        local ctor = rawget(class, "ctor")
        if type(ctor) == "function" then
            ctor(instance, ...)
        end
    end
    return instance
end

function class_methods:get_name()
    return assert_class(self).name
end

function class_methods:is_subclass(target)
    assert_class(self)
    assert_class(target)
    return is_subclass_of(self, target)
end

function class_methods:is_instance(value)
    assert_class(self)
    local info = instance_info[value]
    return info ~= nil and is_subclass_of(info.class, self)
end

function object_methods:get_class()
    return instance_info[self].class
end

function object_methods:get_class_name()
    local class = instance_info[self].class
    return class_info[class].name
end

function object_methods:is_a(target)
    assert_class(target)
    return is_subclass_of(instance_info[self].class, target)
end

function object_methods:is_destroyed()
    return instance_info[self].destroyed
end

function object_methods:destroy()
    local info = instance_info[self]
    if info.destroyed then
        return false
    end
    info.destroyed = true

    local current = info.class
    while current ~= nil do
        local dtor = rawget(current, "dtor")
        if type(dtor) == "function" then
            dtor(self)
        end
        current = class_info[current].base
    end
    return true
end

local function define_class(name, base)
    if type(name) ~= "string" or name == "" then
        raise("INVALID_CLASS_NAME", "class name must be a non-empty string", {
            class = name,
        })
    end
    if base ~= nil and class_info[base] == nil then
        raise("INVALID_BASE_CLASS", "base must be a class created by FClass", {
            class = name,
            base = tostring(base),
        })
    end

    local class = { super = base }
    class_info[class] = { name = name, base = base }
    setmetatable(class, {
        __index = function(_, key)
            local method = class_methods[key]
            if method ~= nil then
                return method
            end
            if base ~= nil then
                return base[key]
            end
            return nil
        end,
    })
    return class
end

return setmetatable(FClass, {
    __call = function(_, name, base)
        return define_class(name, base)
    end,
})
