return {
    LoginPanel = {
        presenter = "LuaUIFramework.App.UI.Login.LoginPresenter",
        singleton = true,
        cachePolicy = "DestroyOnClose",
        assets = {
            unreal = "/Game/UI/Login/WBP_LoginPanel",
            unity = "UI/Login/LoginPanel",
        },
        requiredBindings = {
            title = "Text",
            account_text = "Text",
            login_button = "Button",
            status_text = "Text",
            avatar = "Image",
        },
    },
}
