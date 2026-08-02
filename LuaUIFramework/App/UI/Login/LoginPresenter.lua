local FBasePresenter = require("LuaUIFramework.Shared.Core.FBasePresenter")
local LoginPresenter = {}
LoginPresenter.__index = LoginPresenter
setmetatable(LoginPresenter, { __index = FBasePresenter })

function LoginPresenter.new(services)
    local instance = FBasePresenter.initialize({ services = services })
    return setmetatable(instance, LoginPresenter)
end

function LoginPresenter:on_create(view, params)
    FBasePresenter.on_create(self, view, params)
    self.account = self.params.account or ""
end

function LoginPresenter:on_bind()
    self:track(self.view:button("login_button"):on_click(function()
        local succeeded, message = self.services.login(self.account)
        self.view:text("status_text"):set_text(succeeded and "登录成功" or (message or "登录失败"))
    end))
end

function LoginPresenter:on_open(params)
    FBasePresenter.on_open(self, params)
    self.account = self.params.account or ""
    self.view:text("title"):set_text("登录")
    self.view:text("account_text"):set_text(self.account)
    self.view:text("status_text"):set_text("")
    self.view:image("avatar"):set_source(self.params.avatar or "avatar/default")
end

return LoginPresenter
