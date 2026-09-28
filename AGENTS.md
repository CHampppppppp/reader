# Reader 工程规范

## 产品范围
macOS 原生微信读书悬浮浏览器，另有 Windows 11 x64 原型。Windows 先验证透明窗口与原生隐藏，再补齐完整客户端。通过官方网页登录和阅读，进度、笔记和时长由官方网页处理。不读取或记录登录凭据，不实现私有同步接口。

## 结构与命名
- `Sources/Reader/`：Swift 应用源码，按职责拆分，类型与文件使用 PascalCase。
- `Sources/Reader.Windows/`：C# / WPF / WebView2 Windows 原型，类型与文件使用 PascalCase；不复制共享网页脚本。
- `Tests/Reader.Windows.Tests/`：Windows 离线 HTML 夹具与原型验收说明；夹具不连接真实账号。
- `Resources/`：应用元数据、网页外观适配脚本、Logo 原始 PNG 与提示词、AppIcon.icns 应用图标。
- `scripts/`：本地构建和验证脚本，使用小写连字符命名。
- `Tests/`：必要的行为验证。
- `build/`：本地生成的 app 与 AppIcon.iconset 多尺寸图标中间产物，不提交；未经用户确认不删除产物。
- `.build/`：Swift Package Manager 缓存，不提交。
- Windows 的 `bin/`、`obj/` 为构建缓存，不提交；本地 SDK 如需使用放入 `.build/`，不安装全局依赖；未经确认不删除。
- 根目录保留 Package.swift、README.md、AGENTS.md 和 .gitignore。
新增目录先更新本文件。临时调查文件不要写进源码目录。

## 工程约束
- 使用系统 AppKit、WebKit、Carbon，不引入全局依赖。
- 主线程管理窗口与 WebKit。隐藏使用 orderOut，不能仅将透明度设为零。
- 以 accessory/LSUIElement 方式运行，不显示 Dock 入口。
- 快捷键注册失败必须可见，菜单入口关闭前必须保证快捷键可用。
- 全局隐藏／显示默认使用 Command + 主键盘数字 0；本次更新按用户要求将旧组合切换到该默认值，之后用户选择仍持久化。
- 性能优先：隐藏热路径先 orderOut，再处理焦点与菜单；不能等待 JavaScript、网络或同步。不得添加周期轮询或自动刷新。验证原生进程和 WebKit 子进程占用，网页繁忙时验证隐藏响应。
- 网页透明样式只作用于 weread.qq.com，可关闭；不修改网页阅读和同步逻辑。
- 阅读背景默认完全透明（alpha=0），本次升级一次性启用透明背景并清除旧底色；正文金色与字号不变，后续用户调整仍可保存。
- macOS WebKit 的原生底色使用 drawsBackground SPI 关闭，调用前检查 setter 是否存在；不可用时明确提示。该兼容逻辑仅用于本地应用，需随系统升级验证像素透明度。
- 阅读正文固定为金色 #D4AF37，覆盖 DOM 文字与官方正文 Canvas 层，不过滤封面、插图或整页。隐藏上一页／下一页按钮，沿用官方左右方向键翻页；不重复注册翻页监听。
- 正文字体使用 PingFang SC 中等字重（500），预排版与显示层同时设置；金色文字增加细暗色轮廓，Canvas 只处理正文层，不添加背景或轮询。
- 阅读页使用 WebKit 100% 页面缩放，DOM 和 Canvas 字号均为此前 50% 缩放时的两倍，书架及登录页保持原比例；正文行高约 1.55、段间距 0.6em。
- 会影响排版的外观样式必须在 documentStart 注入，先于网页脚本测量正文；禁止加载完成后才改变已缓存的正文几何尺寸。外观测试覆盖首轮测量与注入后的尺寸一致性。
- 不将密钥、Cookie、网页正文、token 写入日志或仓库。
- 删除、push、修改系统配置等操作遵守用户给定的审批红线。

## 验证
- Windows 原型使用 WPF 的 WebView2CompositionControl 验证透明合成；默认打开离线夹具，`--website` 才加载官网，`--self-test` 运行离线自动验证。Windows 用微软雅黑字体，macOS 保持苹方。启动脚本必须先于页面脚本执行，隐藏直接调用原生窗口 Hide，不等待网页。
- Windows 原型固定保留托盘入口，默认 Ctrl + 0（主键盘数字 0），不提供快捷键修改；冲突明确提示。此阶段暂不实现设置持久化。WebView2 Runtime 缺失时提示用户安装，不静默修改系统。
- `powershell -File scripts/build-windows.ps1`：在 Windows 用 .NET 10 SDK 构建自带 .NET 运行时的 win-x64 测试包，输出 `build/windows/`。
- `powershell -File scripts/test-windows.ps1`：在 Windows 运行离线外观、透明像素、繁忙网页隐藏／恢复测试；桌面透明合成与交互仍需按夹具说明人工验收。Mac 上交叉编译不代表 Windows 运行验证。
- `bash scripts/test.sh`：验证配置、链接和快捷键规则。测试使用独立 Swift 入口，兼容仅安装 Command Line Tools、没有 XCTest 的环境。
- `bash scripts/build-app.sh`：构建本地 app，执行 ad-hoc 签名。
- `bash scripts/test-window.sh`：隔离、离屏 WebKit 页面忙碌时的原生隐藏及恢复测试，不使用真实账号。
- `bash scripts/test-appearance.sh`：离线 WebKit 夹具验证文字颜色、正文 Canvas 着色及翻页按钮隐藏。
- UI 手动验证：网页加载、置顶、快捷键切换、隐藏后的窗口、透明度、恢复和菜单入口。
- 登录后进度/笔记跨设备同步需要用户扫码并配合验证；未验证不得声称通过。
- 完成代码后委派独立审查子代理：原生代码使用 Swift 审查，网页脚本使用 JavaScript 审查；修复实际问题后交付。
- Windows 原生代码使用 C# 审查子代理；共享脚本有改动时同时回归 macOS 外观验证。

## 界面原则
阅读优先，阅读页隐藏官网顶部导航、侧边工具栏和底部工具栏，仅展示阅读内容；使用 visibility 保留官网测量尺寸，避免改变 Canvas 分页几何。书架及登录入口仍可从原生菜单打开。窗口不创建应用工具栏。设置仅使用菜单，参数自动保存并在重启后沿用；Option + 拖动移动窗口。透明样式不兼容时保留正常网页模式。
