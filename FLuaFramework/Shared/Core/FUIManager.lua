local FUIManager = FClass("FUIManager")

function FUIManager:ctor(options)
    self.runtime = options.runtime
    self.pages = options.pages
    self.services = options.services or {}
    self.require_module = options.require_module or require
    self.instances = {}
    self.next_request_version = 0
end

function FUIManager:get(page_name)
    return self.instances[page_name]
end

function FUIManager:is_open(page_name)
    local instance = self.instances[page_name]
    return instance ~= nil and instance.lifecycle:get_state() == "Opened"
end

function FUIManager:hide(page_name)
    local instance = self.instances[page_name]
    if instance == nil or instance.lifecycle:get_state() ~= "Opened" then
        return false
    end
    instance.presenter:on_hide()
    instance.view:set_visible(false)
    instance.lifecycle:transition_to("Hidden")
    return true
end

function FUIManager:show(page_name)
    local instance = self.instances[page_name]
    if instance == nil or instance.lifecycle:get_state() ~= "Hidden" then
        return false
    end
    instance.lifecycle:transition_to("Opened")
    instance.view:set_visible(true)
    instance.presenter:on_show()
    return true
end

function FUIManager:_finish_open(instance, native_view, expected_version)
    if self.instances[instance.name] ~= instance or instance.request_version ~= expected_version then
        self.runtime:destroy_native_view(native_view)
        return
    end

    local succeeded, failure = xpcall(function()
        instance.view = self.runtime:bind_view(
            instance.name,
            native_view,
            instance.definition.requiredBindings
        )
        instance.lifecycle:transition_to("Created")
        local presenter_module = self.require_module(instance.definition.presenter)
        instance.presenter = presenter_module:new(self.services)
        instance.presenter:on_create(instance.view, instance.params)
        instance.presenter:on_bind()
        instance.lifecycle:transition_to("Opened")
        instance.presenter:on_open(instance.params)
        instance.view:set_visible(true)
        instance.presenter:on_show()
    end, function(err)
        return err
    end)

    if succeeded then
        return
    end
    if instance.presenter ~= nil then
        pcall(instance.presenter.on_unbind, instance.presenter)
        pcall(instance.presenter.on_destroy, instance.presenter)
    end
    if instance.view ~= nil then
        instance.view:destroy()
    else
        self.runtime:destroy_native_view(native_view)
    end
    if self.instances[instance.name] == instance then
        self.instances[instance.name] = nil
    end
    error(failure, 0)
end

function FUIManager:open(page_name, params)
    local definition = self.pages[page_name]
    if definition == nil then
        error(FError:new("PAGE_NOT_REGISTERED", "page is not registered", { page = page_name }), 0)
    end
    local existing = self.instances[page_name]
    if existing ~= nil and definition.singleton then
        return existing
    end
    local asset = definition.assets[self.runtime.platform]
    if asset == nil then
        error(FError:new("ASSET_LOAD_FAILED", "page has no asset for the active platform", {
            page = page_name, platform = self.runtime.platform,
        }), 0)
    end

    self.next_request_version = self.next_request_version + 1
    local instance = {
        name = page_name,
        definition = definition,
        lifecycle = FLifecycle:new(),
        request_version = self.next_request_version,
        params = params or {},
    }
    instance.lifecycle:transition_to("Loading")
    self.instances[page_name] = instance
    local expected_version = instance.request_version
    instance.request = self.runtime:load_view(asset, function(native_view)
        self:_finish_open(instance, native_view, expected_version)
    end)
    return instance
end

function FUIManager:close(page_name, result)
    local instance = self.instances[page_name]
    if instance == nil then return false end
    local state = instance.lifecycle:get_state()
    instance.request_version = instance.request_version + 1
    if state == "Loading" then
        if instance.request ~= nil then instance.request:cancel() end
        instance.lifecycle:transition_to("Unloaded")
        self.instances[page_name] = nil
        return true
    end
    if state == "Opened" or state == "Hidden" or state == "Created" then
        if state == "Opened" then instance.presenter:on_hide() end
        instance.lifecycle:transition_to("Closing")
        instance.presenter:on_close(result)
        instance.presenter:on_unbind()
        instance.presenter:on_destroy()
        instance.view:destroy()
        instance.lifecycle:transition_to("Destroyed")
        self.instances[page_name] = nil
        return true
    end
    return false
end

return FUIManager
