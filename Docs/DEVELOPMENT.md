# Development

[English README](../README.md) · [中文首页](../README.zh-CN.md)

## Build and package

Use current Apple Command Line Tools or Xcode on an Apple Silicon Mac. The build targets `arm64-apple-macosx14.0` and uses system frameworks; no package manager or bundled browser runtime is required.

From the repository root:

```sh
./build.sh
open /tmp/sparky-build/Sparky.app
```

The script builds and ad hoc signs `/tmp/sparky-build/Sparky.app`. It does not install or publish the app. Quit an older running instance before opening a new build.

To create a DMG containing the app and an Applications shortcut:

```sh
./package-dmg.sh
```

Output: `dist/Sparky-<version>-mac-arm64.dmg`. This script rebuilds the app. It does not upload a release or notarize the installer.

## Offline verification

After building, run:

```sh
/tmp/sparky-build/Sparky.app/Contents/MacOS/Sparky --self-test
```

The suite uses a local HTML fixture and nonpersistent WebKit stores. It does not log into Douyin or send real messages. It covers delayed names and avatar addresses, virtual scrolling, bounded rereads, login cancellation, per-account preferences, sign-out recovery, batching, scheduling, duplicate prevention, daylight saving time, recipient checks, receipt evidence and durable records.

Focused suites are available with `--self-test --scan-only`, `--self-test --login-only` or `--self-test --logout-only`.

Native window interaction tests:

```sh
/tmp/sparky-build/Sparky.app/Contents/MacOS/Sparky --window-self-test
```

These use demo data to verify minimum-size enforcement through content/frame/live resize paths, visible controls at the minimum, inset native button hit targets, reversible height-only zoom and fullscreen exclusion, and ⌘W, Dock/menu bar mode changes and full-row sidebar/contact hit areas, selection persistence, search/filtering, review cancellation and compact empty-list layout, always-expanded sidebar navigation and balanced brand spacing, and the transparent title bar/backdrop. For a UI smoke check, use `--ui-smoke`; add `--ui-settings`, `--ui-contacts` or `--ui-history` to select a page. Add `--ui-dark`, `--ui-compact`, `--ui-tall`, `--ui-empty`, `--ui-stress` or `--ui-loading` for appearance and layout checks. These modes use synthetic data only.

The suite compares minimization against an unmodified `NSWindow`. If the session cannot minimize that control window, the acknowledgement check is reported as skipped; native style and hit-target checks still run. Use a normal desktop session to verify Dock minimization.

## Source layout

| Path | Responsibility |
| --- | --- |
| `Sources/main.swift` | App lifecycle, native windows, menus and Dock policy. |
| `Sources/MainWindow.swift` | Native control placement, minimum size enforcement and reversible height-only zoom and fullscreen exclusion. |
| `Sources/Views.swift` | SwiftUI pages and send review. |
| `Sources/Design.swift` | Semantic surfaces, section layout, shared icon and row feedback. |
| `Sources/Model.swift` | Persistent settings, account preferences, plans and delivery records. |
| `Sources/Engine.swift` | On-demand WebKit, login, contact scanning and send verification. |
| `Sources/Avatars.swift` | Restricted avatar loading and thumbnail caching. |
| `Resources/Engine.js` | Conversation discovery, draft checks, dispatch and receipt observation. |
| `Resources/selectors.json` | Message input primitive. |
| `Resources/Fixture.html` | Offline chat fixture. |
| `Tools/Icon.swift` | Original vector artwork used for the application icon. |
| `Assets/AppIcon.png` | README artwork exported from `Resources/Sparky.icns`. |

Keep the application identifier and legacy `Spark` support directory stable to preserve existing login and settings. Never commit `state.json`, login data, private logs or chat screenshots.

## Documentation

Native design decisions and the external skill references are recorded in [Design](DESIGN.md).

`README.md` and `README.zh-CN.md` provide parallel English and Simplified Chinese introductions. Detailed user behavior belongs in the matching `Docs/TUTORIAL*.md` files. Update both languages when changing a feature description, and keep relative links and the shared icon path valid.

Documentation languages do not imply interface localization: the current app UI is Simplified Chinese. Refer to actual Chinese button labels when describing the app in English.

Attribution and icon provenance are in [Third-party notices](../THIRD_PARTY_NOTICES.md).
