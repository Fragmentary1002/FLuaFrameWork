local FUIRouter = FClass("FUIRouter")

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

return FUIRouter
