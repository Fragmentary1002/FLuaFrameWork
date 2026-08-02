local FUIManager = FClass("FUIManager")

function FUIManager:ctor(options)
    self.runtime = options.runtime
    self.logger = options.logger or FILogger:new(self.runtime.platform)
    self.pages = options.pages
    self.layers = options.layers or {}
    self.services = options.services or {}
    self.require_module = options.require_module or require
    self.instances = {}
    self.next_request_version = 0
    self.next_instance_id = 0
end

function FUIManager:_raise(failure, context)
    self.logger:error(failure, context)
    error(failure, 0)
end

function FUIManager:get(page_name)
    return self.instances[page_name]
end

function FUIManager:is_open(page_name)
    local instance = self.instances[page_name]
    return instance ~= nil and instance.lifecycle:get_state() == "Opened"
end

function FUIManager:capture_state(page_name)
    local instance = self.instances[page_name]
    if instance == nil or instance.presenter == nil then return nil end
    local state = instance.lifecycle:get_state()
    if state ~= "Opened" and state ~= "Hidden" then return nil end
    return instance.presenter:on_save_state()
end

function FUIManager:hide(page_name)
    local instance = self.instances[page_name]
    if instance == nil then return false end
    if instance.lifecycle:get_state() == "Loading" then
        instance.desired_visible = false
        return true
    end
    if instance.lifecycle:get_state() ~= "Opened" then return false end
    instance.desired_visible = false
    instance.presenter:on_hide()
    instance.view:set_visible(false)
    instance.lifecycle:transition_to("Hidden")
    return true
end

function FUIManager:show(page_name)
    local instance = self.instances[page_name]
    if instance == nil then return false end
    if instance.lifecycle:get_state() == "Loading" then
        instance.desired_visible = true
        return true
    end
    if instance.lifecycle:get_state() ~= "Hidden" then return false end
    instance.desired_visible = true
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
        if type(self.runtime.mount_view) == "function" then
            self.runtime:mount_view(
                native_view,
                instance.layer,
                self.layers[instance.layer],
                instance.definition.inputMode or "UIOnly"
            )
        end
        instance.view = self.runtime:bind_view(
            instance.name,
            native_view,
            instance.definition.requiredBindings
        )
        instance.lifecycle:transition_to("Created")
        local presenter_module = self.require_module(instance.definition.presenter)
        instance.presenter = presenter_module:new(self.services)
        instance.presenter:on_create(instance.view, instance.params)
        if instance.restore_state ~= nil then
            instance.presenter:on_restore_state(instance.restore_state)
        end
        instance.presenter:on_bind()
        instance.lifecycle:transition_to("Opened")
        instance.presenter:on_open(instance.params)
        if instance.desired_visible then
            instance.view:set_visible(true)
            instance.presenter:on_show()
        else
            instance.view:set_visible(false)
            instance.lifecycle:transition_to("Hidden")
        end
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

function FUIManager:open(page_name, params, restore_state)
    local definition = self.pages[page_name]
    if definition == nil then
        local failure = FError:new("PAGE_NOT_REGISTERED", "page is not registered", { page = page_name })
        self:_raise(failure, { page = page_name, platform = self.runtime.platform })
    end
    local layer_name = definition.layer or "Normal"
    local layer = self.layers[layer_name]
    if layer == nil then
        local failure = FError:new("LAYER_NOT_FOUND", "page layer is not configured", {
            page = page_name,
            layer = layer_name,
            platform = self.runtime.platform,
        })
        self:_raise(failure, { page = page_name, platform = self.runtime.platform })
    end
    local existing = self.instances[page_name]
    if existing ~= nil and definition.singleton then
        return existing
    end
    local asset = definition.assets[self.runtime.platform]
    if asset == nil then
        local failure = FError:new("ASSET_LOAD_FAILED", "page has no asset for the active platform", {
            page = page_name, platform = self.runtime.platform,
        })
        self:_raise(failure, { page = page_name, platform = self.runtime.platform })
    end

    self.next_request_version = self.next_request_version + 1
    self.next_instance_id = self.next_instance_id + 1
    local instance = {
        id = self.next_instance_id,
        name = page_name,
        definition = definition,
        layer = layer_name,
        open_order = self.next_instance_id,
        lifecycle = FLifecycle:new(),
        request_version = self.next_request_version,
        params = params or {},
        desired_visible = true,
        restore_state = restore_state,
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

function FUIManager:close_layer(layer_name)
    if self.layers[layer_name] == nil then
        error(FError:new("LAYER_NOT_FOUND", "UI layer is not configured", {
            layer = layer_name,
            platform = self.runtime.platform,
        }), 0)
    end
    local targets = {}
    for page_name, instance in pairs(self.instances) do
        if instance.layer == layer_name then
            table.insert(targets, { page = page_name, order = instance.open_order })
        end
    end
    table.sort(targets, function(left, right) return left.order > right.order end)
    local count = 0
    for _, target in ipairs(targets) do
        if self:close(target.page) then count = count + 1 end
    end
    return count
end

return FUIManager
