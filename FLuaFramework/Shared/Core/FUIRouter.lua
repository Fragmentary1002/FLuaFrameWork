local FUIRouter = FClass("FUIRouter")

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] ~= nil then return seen[value] end
    local result = {}
    seen[value] = result
    for key, item in pairs(value) do
        result[copy(key, seen)] = copy(item, seen)
    end
    return result
end

function FUIRouter:ctor(manager)
    self.manager = manager
    self.stack = {}
end

function FUIRouter:current() return self.stack[#self.stack] end

function FUIRouter:get_stack()
    local copy = {}
    for index, entry in ipairs(self.stack) do
        copy[index] = { page = entry.page, params = entry.params }
    end
    return copy
end

function FUIRouter:_definition(page_name)
    local definition = self.manager.pages[page_name]
    if definition == nil then
        error(FError:new("PAGE_NOT_REGISTERED", "route page is not registered", { page = page_name }), 0)
    end
    if definition.singleton ~= true then
        error(FError:new("ROUTE_REQUIRES_SINGLETON", "route pages must be singleton", { page = page_name }), 0)
    end
    return definition
end

function FUIRouter:push(page_name, params)
    self:_definition(page_name)
    local current = self:current()
    if current ~= nil and current.page == page_name then return self.manager:get(page_name) end
    if current ~= nil and not self.manager:hide(current.page) then
        error(FError:new("ROUTE_NOT_READY", "current route cannot be hidden", { page = current.page }), 0)
    end
    local succeeded, result = pcall(self.manager.open, self.manager, page_name, params)
    if not succeeded then
        if current ~= nil then self.manager:show(current.page) end
        error(result, 0)
    end
    table.insert(self.stack, { page = page_name, params = params or {} })
    return result
end

function FUIRouter:replace(page_name, params)
    self:_definition(page_name)
    local current = self:current()
    if current ~= nil then
        self.manager:close(current.page)
        table.remove(self.stack)
    end
    local result = self.manager:open(page_name, params)
    table.insert(self.stack, { page = page_name, params = params or {} })
    return result
end

function FUIRouter:back(result)
    if #self.stack <= 1 then return false end
    local current = table.remove(self.stack)
    self.manager:close(current.page, result)
    local previous = self:current()
    if not self.manager:show(previous.page) then
        error(FError:new("ROUTE_NOT_READY", "previous route cannot be shown", { page = previous.page }), 0)
    end
    return true
end

function FUIRouter:reset(page_name, params)
    self:_definition(page_name)
    for index = #self.stack, 1, -1 do
        self.manager:close(self.stack[index].page)
        self.stack[index] = nil
    end
    local result = self.manager:open(page_name, params)
    table.insert(self.stack, { page = page_name, params = params or {} })
    return result
end

function FUIRouter:present(page_name, params)
    local definition = self:_definition(page_name)
    if definition.layer ~= "Modal" then
        error(FError:new("INVALID_MODAL_PAGE", "present requires a page in the Modal layer", {
            page = page_name, layer = definition.layer,
        }), 0)
    end
    return self.manager:open(page_name, params)
end

function FUIRouter:snapshot()
    local routes = {}
    for index, entry in ipairs(self.stack) do
        routes[index] = {
            page = entry.page,
            params = copy(entry.params),
            state = copy(self.manager:capture_state(entry.page)),
        }
    end
    return { version = 1, routes = routes }
end

function FUIRouter:restore(snapshot)
    if type(snapshot) ~= "table"
        or snapshot.version ~= 1
        or type(snapshot.routes) ~= "table"
        or #snapshot.routes == 0 then
        error(FError:new("INVALID_ROUTE_SNAPSHOT", "route snapshot is invalid", {}), 0)
    end

    for _, route in ipairs(snapshot.routes) do
        if type(route) ~= "table" or type(route.page) ~= "string" then
            error(FError:new("INVALID_ROUTE_SNAPSHOT", "route entry is invalid", {}), 0)
        end
        self:_definition(route.page)
    end

    for index = #self.stack, 1, -1 do
        self.manager:close(self.stack[index].page, "restore")
        self.stack[index] = nil
    end

    local previous = nil
    for _, route in ipairs(snapshot.routes) do
        if previous ~= nil then self.manager:hide(previous.page) end
        self.manager:open(route.page, copy(route.params), copy(route.state))
        local entry = { page = route.page, params = copy(route.params) }
        table.insert(self.stack, entry)
        previous = entry
    end
    return self:current()
end

return FUIRouter
