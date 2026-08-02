# 阶段二 Adapter 接入要求

阶段二只实现 Shared Lua 能力，不修改 `FLuaFramework/Adapters/**`。本文件定义 Unreal/UMG/UnLua 与 Unity/UGUI/xLua 后续接入时必须满足的协议。

## 1. 新控件绑定

`FViewBinder` 后续需要把以下逻辑类型映射为公共包装类：

- `Input` → `FIInput`
- `Toggle` → `FIToggle`
- `Progress` → `FIProgress`

控件操作表必须提供：

```lua
Input = {
    is_valid = function() return boolean end,
    set_visible = function(value) end,
    set_text = function(value) end,
    get_text = function() return string end,
    on_changed = function(callback) return { unsubscribe = function() end } end,
}

Toggle = {
    is_valid = function() return boolean end,
    set_visible = function(value) end,
    set_checked = function(value) end,
    is_checked = function() return boolean end,
    on_changed = function(callback) return { unsubscribe = function() end } end,
}

Progress = {
    is_valid = function() return boolean end,
    set_visible = function(value) end,
    set_value = function(value) end,
    get_value = function() return number end,
}
```

Unreal Adapter 应把 EditableText/EditableTextBox、CheckBox、ProgressBar 映射到上述语义；Unity Adapter 应把 InputField/TMP_InputField、Toggle、Slider 或 Image Fill 映射到上述语义。事件解绑必须幂等，原生对象失效后 `is_valid` 必须返回 false。

## 2. 逻辑层挂载

Shared Manager 会在 Runtime 存在 `mount_view` 时调用：

```lua
runtime:mount_view(native_view, layer_name, layer_definition, input_mode)
```

其中 `layer_definition` 包含 `order` 和 `blocksInput`。Unreal 后续应映射到 Viewport 容器、ZOrder、输入模式和命中测试；Unity 后续应映射到 Canvas/Transform 层、Sorting Order、GraphicRaycaster 和输入阻挡。未实现该方法时 Shared 仍维护逻辑层和 `close_layer`，但不会改变原生显示顺序。

## 3. 资源后端注入

宿主通过 `init.create({ asset_backend = backend })` 注入：

```lua
backend:load(address, asset_type, on_success, on_error)
    -> { cancel = function() end }

backend:release(native_asset, asset_type)
```

Unreal 后续应使用软引用/StreamableManager 或项目资源服务；Unity 后续应使用 Addressables、AssetBundle 或项目资源服务。取消必须幂等；若底层无法阻止迟到成功回调，Shared Loader 会立即调用 `release`。业务 Lua 只使用 `{ id, type }`，平台地址只存在于 `FAssets.lua`。

## 4. 日志落点注入

宿主可通过 `init.create({ log_sink = function(record) end })` 注入日志落点。`record` 至少可能包含：

```text
level, message, platform, page, instanceId, layer, lifecycle,
binding, assetId, assetType, errorCode, traceback
```

Unreal 后续应写入 UE_LOG/项目日志系统，Unity 后续应写入 Debug.Log 或项目日志系统。sink 不得反向抛出引擎异常破坏 Shared 清理流程。

## 5. Adapter 验收矩阵

后续实现 Adapter 时，两平台必须运行同一组契约用例：

- Input 设置、读取、变更订阅和解绑一致。
- Toggle 布尔归一化、变更订阅和解绑一致。
- Progress 使用 `[0, 1]`，无平台百分比差异。
- 七个逻辑层的顺序和输入阻挡意图一致。
- 资源成功、失败、取消、迟到释放一致。
- 原生对象销毁后统一产生 `NATIVE_OBJECT_INVALID`。
- 日志字段不因平台不同而缺失。
