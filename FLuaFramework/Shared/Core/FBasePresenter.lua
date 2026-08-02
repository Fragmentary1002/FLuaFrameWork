local FBasePresenter = FClass("FBasePresenter")

local function dispose_reverse(items, method)
    local first_failure = nil
    for index = #items, 1, -1 do
        local handle = items[index]
        items[index] = nil
        local succeeded, failure = pcall(handle[method], handle)
        if not succeeded and first_failure == nil then first_failure = failure end
    end
    return first_failure
end

function FBasePresenter:ctor()
    self.subscriptions = {}
    self.requests = {}
    self.resources = {}
    self.unbound = false
end

function FBasePresenter:track(subscription)
    if type(subscription) ~= "table" or type(subscription.unsubscribe) ~= "function" then
        error(FError:new("INVALID_SUBSCRIPTION", "subscription must expose unsubscribe", {}), 0)
    end
    table.insert(self.subscriptions, subscription)
    return subscription
end

function FBasePresenter:track_request(request)
    if type(request) ~= "table" or type(request.cancel) ~= "function" then
        error(FError:new("INVALID_CANCELABLE", "request must expose cancel", {}), 0)
    end
    table.insert(self.requests, request)
    return request
end

function FBasePresenter:track_resource(resource)
    if type(resource) ~= "table" or type(resource.release) ~= "function" then
        error(FError:new("INVALID_RESOURCE", "resource must expose release", {}), 0)
    end
    table.insert(self.resources, resource)
    return resource
end

function FBasePresenter:on_create(view, params)
    self.view = view
    self.params = params or {}
end

function FBasePresenter:on_bind() end
function FBasePresenter:on_open(params) self.params = params or {} end
function FBasePresenter:on_show() end
function FBasePresenter:on_hide() end
function FBasePresenter:on_close(result) self.close_result = result end
function FBasePresenter:on_save_state() return {} end
function FBasePresenter:on_restore_state(_) end

function FBasePresenter:on_unbind()
    if self.unbound then return end
    self.unbound = true
    local failure = dispose_reverse(self.subscriptions, "unsubscribe")
    local request_failure = dispose_reverse(self.requests, "cancel")
    local resource_failure = dispose_reverse(self.resources, "release")
    failure = failure or request_failure or resource_failure
    if failure ~= nil then error(failure, 0) end
end

function FBasePresenter:on_destroy()
    self.view = nil
    self.params = nil
end

return FBasePresenter
