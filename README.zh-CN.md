<p align="center">
  <img src="Assets/AppIcon.png" width="128" alt="Sparky 应用图标">
</p>

# Sparky

**让联系，持续发生。**

轻量的 macOS 菜单栏应用，为选定的抖音聊天会话定时发送一条消息。登录账号、选好好友、设定时间即可。使用系统 WebKit，按需启动，任务结束后释放网页。

[English](README.md) · **简体中文**

[版本下载](https://github.com/Er1cG1ao/Sparky/releases) · [使用教程](Docs/TUTORIAL.zh-CN.md) · [开发说明（英文）](Docs/DEVELOPMENT.md) · [问题反馈](https://github.com/Er1cG1ao/Sparky/issues)

## 能做什么

- **选择聊天对象：** 搜索、多选已有私聊和群聊，显示并缓存联系人头像。
- **记住每个账号：** 按抖音账号分别保存好友选择，退出登录及重启后保留。
- **自动完成登录后续流程：** 登录成功后收起聊天窗口，在后台读取联系人，完成后释放引擎。
- **按计划发送：** 自定义消息和每日时间，也可核对名单后手动执行一批。
- **记录实际结果：** 为每个会话显示服务器确认、页面确认、拒绝或结果待确认。
- **常驻菜单栏：** 主窗口打开时显示 Dock 图标并支持 ⌘Tab；按 ⌘W 关闭后回到菜单栏模式。

使用 Swift、SwiftUI 和 AppKit 构建，无需附带 Chromium、Python 运行时或独立后台服务。文档提供中英文版本；应用界面目前为简体中文。

## 安装与开始使用

要求 **Apple Silicon（M 系列）Mac，macOS 14 或更高版本**。暂不提供 Intel 安装包。

1. 在[最新正式版](https://github.com/Er1cG1ao/Sparky/releases/latest)的 **Assets** 中下载 DMG；历史版本见[版本页面](https://github.com/Er1cG1ao/Sparky/releases)。
2. 完全退出旧 Spark / Sparky，打开镜像，把 `Sparky.app` 拖入 **Applications（应用程序）**。
3. 在“设置”打开登录窗口并登录抖音；成功后窗口自动收起，开始读取联系人。
4. 在“联系人”勾选会话，在“发送计划”设置消息和每日时间。
5. 先用自己的测试会话执行一次“立即执行…”，核对实际聊天记录后再开启定时。

请保持 Sparky 运行。关闭主窗口会留在菜单栏，退出应用则停止调度；Mac 需保持唤醒才能发送。唤醒补发、账号切换及发送状态详见[使用教程](Docs/TUTORIAL.zh-CN.md)。

当前安装包采用 ad hoc 签名，**尚未经过 Apple 公证**。首次打开如被 macOS 拦截，请先核对下载来源，再到“隐私与安全性”中允许此应用，无需关闭系统安全保护。

## 支持范围与隐私

- 面向**抖音**，通过抖音网页聊天工作。支持已有会话，列表可能不包含折叠或陌生人会话。
- 消息逐人发送。发送成功**不保证**送达、对方回复或火花更新；结果不确定时不会自动重试。
- 登录使用本应用的 WebKit 网站数据存储。退出登录会清除该会话并暂停计划，不影响手机或 Safari。
- 账号选择、消息设置和近期发送元数据保存在本机。网页连接抖音；头像从支持的抖音／字节 HTTPS CDN 加载，不附带登录 Cookie。Sparky 没有额外上传服务器。
- 网页结构或站点限制变化可能影响登录、读取及发送。本项目与抖音官方无关联，详见[本地数据与限制](Docs/TUTORIAL.zh-CN.md#本地数据与隐私)。

## 从源码构建

安装当前版本的 Apple Command Line Tools 或 Xcode，然后运行：

```sh
git clone https://github.com/Er1cG1ao/Sparky.git
cd Sparky
./build.sh
```

产物为 `/tmp/sparky-build/Sparky.app`。构建脚本面向 Apple Silicon，不会安装或发布应用。打包、离线测试及源码结构见[开发说明（英文）](Docs/DEVELOPMENT.md)。

## 反馈与参与

普通问题和建议可提交到 [Issues](https://github.com/Er1cG1ao/Sparky/issues)。请附上 Sparky 版本、macOS 版本、复现步骤、预期与实际结果。日志和截图先移除账号标识、私人消息及其他个人信息，不要上传登录 Cookie。

[中文教程](Docs/TUTORIAL.zh-CN.md) · [English guide](Docs/TUTORIAL.md) · [开发说明（英文）](Docs/DEVELOPMENT.md)

## 许可证与来源

[MIT](LICENSE)。Sparky 改编了 [DouYinSparkFlow](https://github.com/2061360308/DouYinSparkFlow) 的输入脚本及会话发现思路，署名与素材说明见[第三方声明](THIRD_PARTY_NOTICES.md)。应用图标由 [`Tools/Icon.swift`](Tools/Icon.swift) 中的原创路径绘制。
