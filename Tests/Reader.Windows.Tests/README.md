# Windows 原型验收

第一阶段，目标为 Windows 11 x64；需要 .NET 10 SDK 构建、Evergreen WebView2 Runtime 运行。默认不访问官网。自动测试拦截全部 WebView 请求，夹具通过模拟官网地址测试共享脚本，不使用真实账号；浏览器运行时自身的后台活动不在此拦截范围内。

```powershell
powershell -File scripts/test-windows.ps1
build/windows/Qingdu.Windows.exe
# 明确打开官网，登录与阅读需人工验证
build/windows/Qingdu.Windows.exe --website
```

自动验证：首轮排版与重注入一致、DOM 金色、Canvas 金色像素、网页透明像素、工具栏隐藏、原生窗口在网页持续忙碌时隐藏和恢复。测试输出只含固定检查名及耗时，不输出网页正文、账号或 Cookie。45 秒超时判失败。

人工验收（自动 PNG 透明不等于桌面合成透明）：

- 把窗口放到浅色、深色及复杂桌面上，确认桌面能透出、金色文字清晰、Canvas 色块与参考色块一致。
- 在 100%、150%、200% 缩放和多显示器间验证文字、Alt 拖动、窗口边缘缩放与鼠标点击；完全透明空白可能穿透点击，必须记录实际行为。
- 在其他应用中按 Ctrl + 0（主键盘数字 0），确认窗口消失、恢复；快捷键被占用时提示且托盘可恢复。Alt + F4 应隐藏，托盘退出应结束进程。
- 通过托盘切换深色底，验证透明不适用时可继续阅读。
- 任务管理器同时记录 Qingdu.Windows 和全部所属 msedgewebview2 子进程的 CPU、内存，比较静止、翻页、隐藏状态。WebView2CompositionControl 内部使用图形捕获，不能将此方案描述为没有捕获开销；应用不另加轮询、截图循环或自动刷新。
- 官网模式需扫码后验证阅读与翻页；手机进度、笔记同步需用户配合验证。

当前原型不提供：快捷键配置、设置与窗口位置持久化、再次启动恢复已有实例、安装器和发布签名。新开实例会有独立窗口；托盘入口始终保留。原型和自动测试各用独立 `%LOCALAPPDATA%/Qingdu/Prototype/<随机标识>/`，官网模式用 `%LOCALAPPDATA%/Qingdu/WebView2/Profile/`；按项目规则不会自动删除这些缓存。

2026-09-28 验证记录：

- Mac 使用项目缓存内的 .NET 10.0.100 SDK 交叉编译与 win-x64 自包含构建成功，0 警告、0 错误；可复制完整 `build/windows/` 目录到 Windows，不能只复制 exe。也可解压 `build/Qingdu-Windows-prototype-x64.zip`。
- 独立 C# / JavaScript 审查通过；Chrome 离线验证确认 document-created 时根节点尚不存在，修复后首轮测量与最终字体、行高和段间距一致，正文金色且样式仅注入一次。
- macOS 策略、快捷键、WebKit 外观和繁忙网页隐藏／恢复测试通过。macOS 打包编译成功，但 ad-hoc 签名被产物中的 Finder 元数据阻塞，未将该打包记为通过。
- Windows 实测状态：待验证。以上结果均不能替代 Windows 透明合成、输入、性能及 WebView2 自动测试验收。
