# FLuaFrameWork

阶段一提供跨 Unreal/Unity 的 Lua UI 最小闭环。共享代码不能引用 `UE.*`、`CS.*` 或 `UnityEngine.*`。

## Unreal bridge

UnLua 宿主向 `FUnrealRuntime:new(bridge)` 注入：

- `load_widget(asset, callback) -> { cancel = function }`
- `find_widget(root, logical_id) -> UWidget|nil`
- `get_widget_type(widget) -> "Text"|"Button"|"Image"`
- `make_widget_ops(widget) -> operations`
- `make_view_ops(root) -> operations`
- `destroy_native_view(root)`

## Unity bridge

xLua 宿主向 `FUnityRuntime:new(bridge)` 注入：

- `load_prefab(asset, callback) -> { cancel = function }`
- `find_component(root, logical_id) -> Component|nil`
- `get_component_type(component) -> "Text"|"Button"|"Image"`
- `make_component_ops(component) -> operations`
- `make_view_ops(root) -> operations`
- `destroy_native_view(root)`

两个原生 Login 资源必须暴露 `title`、`account_text`、`login_button`、`status_text`、`avatar`。开发环境绑定失败时页面不会进入 Opened，错误上下文包含 page、platform、binding、expected 和 actual。

## 验证

```powershell
npm install
npm test
npm run check:lua
rg -n "UE\.|UnityEngine\.|CS\." LuaUIFramework/Shared LuaUIFramework/App
```
