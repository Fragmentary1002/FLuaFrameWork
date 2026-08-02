local FBasePresenter = FClass("FBasePresenter")

function FBasePresenter:ctor()
    self.subscriptions = {}
    self.unbound = false
end

function FBasePresenter:track(subscription)
    if type(subscription) ~= "table" or type(subscription.unsubscribe) ~= "function" then
        error(FError:new("INVALID_SUBSCRIPTION", "subscription must expose unsubscribe", {}), 0)
    end
    table.insert(self.subscriptions, subscription)
    return subscription
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

function FBasePresenter:on_unbind()
    if self.unbound then
        return
    end
    self.unbound = true
    for index = #self.subscriptions, 1, -1 do
        self.subscriptions[index]:unsubscribe()
        self.subscriptions[index] = nil
    end
end

function FBasePresenter:on_destroy()
    self.view = nil
    self.params = nil
end

return FBasePresenter
