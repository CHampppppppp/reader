# Reader 工程规范

## 产品范围
macOS 原生微信读书悬浮浏览器，另有 Windows 11 x64 原型。Windows 先验证透明窗口与原生隐藏，再补齐完整客户端。通过官方网页登录和阅读，进度、笔记和时长由官方网页处理。不读取或记录登录凭据，不实现私有同步接口。

## 结构与命名
- `mac/`：macOS 独立工程根目录；`Package.swift`、`Sources/Reader/`、`Tests/ReaderTests/`、`Resources/` 和 `scripts/` 分别放包定义、Swift 源码、测试、平台资源和构建验证脚本。
- `windows/`：Windows 独立工程根目录；`Sources/Reader.Windows/`、`Tests/Reader.Windows.Tests/`、`Resources/` 和 `scripts/` 分别放 C# / WPF 工程、离线夹具与验收说明、平台网页脚本、PowerShell 构建验证脚本。
- `mac/Resources/appearance.js` 与 `windows/Resources/appearance.js` 各保存一份独立网页脚本；构建和测试只读取当前平台资源，不跨目录引用。通用外观修复需要同步时分别修改并验证两份；平台差异可独立维护。macOS 的 Info.plist、AppIcon.icns、Logo 原始 PNG 与提示词放在 `mac/Resources/`；Windows 的 AppIcon.ico 放在 `windows/Resources/`，供可执行文件和托盘图标使用。
- 类型与源码文件使用 PascalCase，脚本使用小写连字符命名。临时调查文件不要写进源码目录。
- `mac/build/`、`windows/build/`：各平台本地产物，不提交；未经用户确认不删除。
- `mac/.build/`：Swift Package Manager 和 Swift 测试缓存；Windows 的 `bin/`、`obj/` 为 .NET 构建缓存，均不提交。
- 根目录 `.build/` 可存放本地 SDK 和临时验证缓存，不安装全局依赖。历史根目录 `build/` 与 `.build/` 产物保留，不自动删除；新构建使用各平台产物目录。
- 根目录保留 README.md、AGENTS.md 和 .gitignore。文档中的命令默认从仓库根目录执行，平台脚本自行定位各自工程根目录。
新增目录先更新本文件。移动文件保留内容，历史产物未经确认不清理。

## 工程约束
- 使用系统 AppKit、WebKit、Carbon，不引入全局依赖。
- 主线程管理窗口与 WebKit。隐藏使用 orderOut，不能仅将透明度设为零。
- 以 accessory/LSUIElement 方式运行，不显示 Dock 入口。
- 快捷键注册失败必须可见，菜单入口关闭前必须保证快捷键可用。
- 全局隐藏／显示默认使用 Command + 主键盘数字 0；本次更新按用户要求将旧组合切换到该默认值，之后用户选择仍持久化。
- macOS 阅读窗口内按 Command + Esc 返回微信读书选书首页；由原生窗口处理，不重复注册网页监听，也不注册全局返回快捷键。原生弹窗打开时保留弹窗的键盘处理。
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
- Windows 原型固定保留托盘入口，默认 Alt + 0（主键盘数字 0）全局隐藏／恢复，不提供快捷键修改；冲突明确提示。Windows 窗口使用 Alt + 拖动移动；官网模式提供托盘返回选书页入口，Alt + Esc 仅在本窗口激活时返回选书页，窗口失焦时释放该系统组合键。此阶段暂不实现设置持久化。WebView2 Runtime 缺失时提示用户安装，不静默修改系统。
- `powershell -File windows/scripts/build-windows.ps1`：在 Windows 用 .NET 10 SDK 构建自带 .NET 运行时的 win-x64 测试包，输出 `windows/build/`。
- `powershell -File windows/scripts/test-windows.ps1`：在 Windows 运行离线外观、透明像素、繁忙网页隐藏／恢复测试；桌面透明合成与交互仍需按夹具说明人工验收。Mac 上交叉编译不代表 Windows 运行验证。
- `bash mac/scripts/test.sh`：验证配置、链接和快捷键规则。测试使用独立 Swift 入口，兼容仅安装 Command Line Tools、没有 XCTest 的环境。
- `bash mac/scripts/build-app.sh`：构建本地 app，执行 ad-hoc 签名。
- `bash mac/scripts/test-window.sh`：隔离、离屏 WebKit 页面忙碌时的原生隐藏及恢复测试，不使用真实账号。
- `bash mac/scripts/test-appearance.sh`：离线 WebKit 夹具验证文字颜色、正文 Canvas 着色及翻页按钮隐藏。
- UI 手动验证：网页加载、置顶、快捷键切换、隐藏后的窗口、透明度、恢复和菜单入口。
- 登录后进度/笔记跨设备同步需要用户扫码并配合验证；未验证不得声称通过。
- 完成代码后委派独立审查子代理：原生代码使用 Swift 审查，网页脚本使用 JavaScript 审查；修复实际问题后交付。
- Windows 原生代码使用 C# 审查子代理；任一平台网页脚本有改动时验证该平台；同步修改两份时分别验证。

## 界面原则
阅读优先，阅读页隐藏官网顶部导航、侧边工具栏和底部工具栏，仅展示阅读内容；使用 visibility 保留官网测量尺寸，避免改变 Canvas 分页几何。书架及登录入口仍可从原生菜单打开。窗口不创建应用工具栏。设置仅使用菜单，参数自动保存并在重启后沿用；Option + 拖动移动窗口。透明样式不兼容时保留正常网页模式。
