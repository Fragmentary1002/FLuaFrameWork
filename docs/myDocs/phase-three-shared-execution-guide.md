# 阶段三 Shared-only 执行说明

## 目的

阶段三只继续实现 Shared Lua 能力，不修改、不补齐、也不执行 Unreal/Unity Adapter 功能。

对应实施计划：

`docs/superpowers/plans/2026-08-02-multi-engine-lua-ui-framework-phase-three-common-capabilities.md`

## 当前基线

阶段二已提交：

```text
d1482aa feat: 完成阶段二共享 UI 能力
```

当前全仓库基线为：

```text
npm test          -> 73 passed, 0 failed
npm run check:lua -> parsed 24 registered framework modules, 4 config/app modules and 2 entry modules
```

`npm test` 会执行 Adapter 契约与双平台集成用例，因此它只用于记录阶段二基线，不作为阶段三循环命令。

## 应该执行的任务

严格按以下顺序执行：

1. 建立 `Tests/SharedTestBootstrap.lua`、`Tests/run-shared.lua` 和 `Tests/check-shared.lua`。
2. 为 `FBasePresenter` 增加请求与资源清理袋。
3. 实现纯 Lua `FILocalization` 与 `FLocales`。
4. 让 `FUIManager` 保存 Loading 期间的 `desired_visible`。
5. 为 `FUIManager/FUIRouter` 增加 Presenter 状态快照与导航恢复。
6. 执行 Shared-only 验收。

允许修改：

```text
FLuaFramework/Shared/**
FLuaFramework/Config/FLocales.lua
FLuaFramework/register.lua
Tests/SharedTestBootstrap.lua
Tests/run-shared.lua
Tests/check-shared.lua
Tests/Fixtures/FFakeRuntime.lua
Tests/Fixtures/FMockView.lua
Tests/Unit/FBasePresenterSpec.lua
Tests/Unit/FILocalizationSpec.lua
Tests/Unit/FUILayerSpec.lua
Tests/Unit/FUIRouterAsyncSpec.lua
Tests/Unit/FUIStateRecoverySpec.lua
package.json
docs/myDocs/phase-three-shared-execution-guide.md
```

## 不应该执行的内容

不要修改：

```text
FLuaFramework/Adapters/**
init.lua
main.lua
```

不要运行或改动以下测试：

```text
Tests/Contract/**
Tests/Unit/FViewBinderSpec.lua
Tests/Unit/FInitSpec.lua
Tests/Unit/FRegisterSpec.lua
Tests/Integration/FUIManagerSpec.lua
Tests/Integration/LoginPanelSpec.lua
Tests/Integration/FMainSpec.lua
```

阶段三不实现：

- Unreal UMG 或 Unity UGUI 控件映射；
- `FViewBinder` 的 List/Animation 工厂；
- Unreal/Unity 层级挂载；
- Addressables、AssetBundle、StreamableManager 或软引用后端；
- Adapter 契约测试工具；
- 虚拟列表、对象池和原生动画。

这些能力需要真实平台 Adapter 才能形成可验证闭环，应单独安排后续计划。接口参考保留在 `docs/myDocs/phase-two-adapter-requirements.md`。

## 阶段三测试命令

完成修订计划 Task 1 后，开发循环只运行：

```powershell
npm run test:shared
npm run check:shared
```

最终目标：

```text
npm run test:shared  -> 68 shared passed, 0 failed
npm run check:shared -> parsed 22 shared framework modules and 5 config/app modules
```

静态检查：

```powershell
node Tests/check-requires.js
rg -n "UE\.|UnityEngine\.|CS\." FLuaFramework/Shared FLuaFramework/App
git diff --check
```

预期：

- `check-requires.js` 输出 `framework require check passed`；
- `rg` 无输出并返回退出码 1，表示没有平台 API 泄漏；
- `git diff --check` 无输出并返回退出码 0。

## Adapter 范围检查

交接前运行：

```powershell
git diff --name-only -- FLuaFramework/Adapters Tests/Contract Tests/Integration Tests/Unit/FViewBinderSpec.lua
```

预期无输出。如果出现文件：

1. 停止阶段三执行；
2. 不继续修改该 Adapter 文件；
3. 将所需接口补充到 `phase-two-adapter-requirements.md`；
4. 恢复到 Shared-only 方案，或另开 Adapter 实施计划。

## 完成判定

只有同时满足以下条件，阶段三才算完成：

- Shared-only 两个命令达到目标结果；
- Adapter 范围检查无输出；+ 
- Presenter 能对称释放订阅、请求和资源；
- 本地化和状态恢复由纯 Lua 单元测试覆盖；
- Loading 页面连续导航不会产生同时可见的旧页面；
- 快照不保存 View、原生对象、回调、订阅或资源句柄。
