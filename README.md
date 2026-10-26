<p align="center">
  <img src="Assets/AppIcon.png" width="128" alt="Sparky app icon">
</p>

# Sparky

**Keep your Douyin connections glowing.**

A lightweight macOS menu bar app for sending a daily message to your chosen Douyin conversations. Sign in, pick your friends, and set a time. Sparky uses the system WebKit engine when needed and releases the page after each task.

**English** · [简体中文](README.zh-CN.md)

[Download](https://github.com/Er1cG1ao/Sparky/releases) · [User guide](Docs/TUTORIAL.md) · [Development](Docs/DEVELOPMENT.md) · [Report an issue](https://github.com/Er1cG1ao/Sparky/issues)

## What it does

- **Choose your conversations:** search and select existing private or group chats, with cached profile pictures.
- **Remember each account:** keep separate selections for each Douyin account, including across sign-outs and restarts.
- **Finish signing in automatically:** hide the chat window after successful login, read contacts in the background, then release the engine.
- **Send on your schedule:** configure a message and daily time, or review and start a batch manually.
- **Show the evidence:** record server confirmation, page confirmation, rejection, or an uncertain result for each recipient.
- **Stay in the menu bar:** open the main window for a Dock icon and ⌘Tab access; close it with ⌘W to return to menu bar mode.

Built with Swift, SwiftUI and AppKit. No bundled Chromium, Python runtime or separate background service. These docs are available in English and Simplified Chinese; the app interface currently uses Simplified Chinese.

## Install and start

Requires **Apple Silicon (M-series), macOS 14 or later**. Intel installers are not currently provided.

1. Download the DMG from **Assets** in the [latest stable release](https://github.com/Er1cG1ao/Sparky/releases/latest). See [Releases](https://github.com/Er1cG1ao/Sparky/releases) for previous versions.
2. Quit any older Spark / Sparky instance, open the DMG, and drag `Sparky.app` into **Applications**.
3. In Settings (`设置`), open the login window and sign in to Douyin. The window hides automatically while contacts are read.
4. Select conversations under Contacts (`联系人`), then set your message and time under Send Plan (`发送计划`).
5. Try **Run now…** (`立即执行…`) with your own test conversation and check the actual chat before enabling the daily plan.

Keep Sparky running. Closing the main window leaves it in the menu bar; quitting stops scheduling. The Mac must be awake to send. See the [guide](Docs/TUTORIAL.md) for wake-up behavior, account switching and delivery results.

Builds use ad hoc signing and are **not Apple-notarized**. If macOS blocks first launch, verify the download source and allow the app in **Privacy & Security**. Disabling system security protections is not required.

## Scope and privacy

- Works with **Douyin**, through its web chat. Existing conversations are supported; folded or stranger conversations may be missing from the list.
- Messages are sent one recipient at a time. A successful send does **not** guarantee delivery, a reply, or a renewed streak. Uncertain sends are not automatically retried.
- Login uses the app's WebKit website store. Signing out clears that session and pauses the plan; phone and Safari sessions are unaffected.
- Account selections, message settings and recent send metadata stay on your Mac. Web chat connects to Douyin; avatars load from supported Douyin/ByteDance HTTPS CDNs without login cookies. Sparky has no separate upload server.
- Site changes or restrictions can interrupt login, contact reading or sending. This project is not affiliated with Douyin. See [data storage and limitations](Docs/TUTORIAL.md#local-data-and-privacy).

## Build from source

Install current Apple Command Line Tools or Xcode, then run:

```sh
git clone https://github.com/Er1cG1ao/Sparky.git
cd Sparky
./build.sh
```

Output: `/tmp/sparky-build/Sparky.app`. The script targets Apple Silicon; building does not install or publish the app. Packaging, offline tests and source layout are documented in [Development](Docs/DEVELOPMENT.md).

## Help and contribute

For bugs and suggestions, open an [Issue](https://github.com/Er1cG1ao/Sparky/issues) with your Sparky version, macOS version, reproduction steps, and expected versus actual behavior. Remove account identifiers, private messages and other personal information from logs or screenshots. Never upload login cookies.

[English guide](Docs/TUTORIAL.md) · [中文教程](Docs/TUTORIAL.zh-CN.md) · [Development](Docs/DEVELOPMENT.md)

## License and origins

[MIT](LICENSE). Sparky adapts the input primitive and conversation discovery concepts from [DouYinSparkFlow](https://github.com/2061360308/DouYinSparkFlow). Attribution and artwork details are in [Third-party notices](THIRD_PARTY_NOTICES.md). The app icon is drawn from the original paths in [`Tools/Icon.swift`](Tools/Icon.swift).
