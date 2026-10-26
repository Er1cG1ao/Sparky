# Sparky user guide

**English** · [简体中文](TUTORIAL.zh-CN.md) · [Back to README](../README.md)

## Sign in and read contacts

Open Settings (`设置`) and choose **Open login window** (`打开登录窗口`). Complete Douyin's login and any verification it requests. Sparky waits for both the chat page and an identified account, then hides the window and reads contacts automatically. Waiting for login is limited to five minutes; close the login window or choose **Cancel login** (`取消登录`) to cancel.

Contact rows can appear before their names and avatars have loaded. Sparky waits for each visible set of rows to stabilize before scrolling, including later rows in the virtualized list. Missing names, or long numeric placeholders without an avatar, keep the scan waiting. It reads avatar addresses without requiring image downloads to succeed; named contacts without a supported avatar remain usable.

If participant data does not become ready, Sparky waits and rereads the list once. Failed reads do not replace the same account's existing contacts or selections. Scanning is bounded rather than retried indefinitely. You can manually choose **Refresh account and contacts** (`刷新账号与联系人`) after the page has recovered.

The list contains existing conversations, including groups. Folded or stranger lists may not be included. Avatars load on demand; a name initial or group symbol appears when an avatar cannot be loaded.

## Choose conversations and switch accounts

Under Contacts (`联系人`), search for a person or group and toggle the conversations you want. **Select current list** (`全选当前列表`) and **Deselect** (`取消选择`) apply to the currently filtered list. Click anywhere on a contact row to toggle it, or switch between All (`全部`) and Selected (`已选`) above the list.

Selections are saved under the stable Douyin account UID and conversation IDs. Signing out or restarting does not erase these preferences. After signing back in, Sparky restores selected conversations that appear in the refreshed list. Remembered conversations absent from one scan stay remembered and can be restored by a later scan. Explicit selection changes update those preferences.

To switch accounts, sign out using Settings or the button beside the account name at the bottom of the sidebar, then sign in again. Signing out clears the app's WebKit login, current account and current contact list, and pauses the daily plan. Saved selections for all accounts, the message template and send records are retained. Phone and Safari sessions are unaffected.

Sign-out is disabled during an operation. If the app is interrupted while clearing login data, it resumes cleanup next launch and blocks reconnection and sending until cleanup completes. Switching to a different account disables the previous plan; a plan paused by sign-out stays paused after login. Enable it manually after checking the restored selection.

Upgrading migrates the currently saved account selection. Selections already erased by older versions cannot be recovered.

## Set a message and daily time

In Send Plan (`发送计划`), enter a single-line message of up to **500 UTF-16 code units**, select a time and enable the daily plan. Try **Run now…** (`立即执行…`) with your own test conversation first, review the recipient list, and check the actual chat afterwards.

- Scheduling follows the Mac's current time zone. Sparky must be running; it does not wake a sleeping Mac.
- After wake, it can catch up on today's unexecuted plan. It does not replay missed tasks from previous days.
- Enabling a plan or changing its time after today's chosen time schedules the next run for tomorrow.
- A manual batch also claims today's automatic slot to avoid another automatic send. You can still explicitly confirm another manual batch.
- Stopping a batch prevents subsequent recipients; it waits for the current conversation to finish.
- Clearing send history does not rearm today's daily task.

Sparky uses one WebKit page and sends sequentially. It checks the selected account, recipient and draft before dispatch, leaves a different existing draft untouched, and triggers each send once. Actual dispatches are at least one second apart. Receipt waiting is bounded at about 12 seconds, without an extra fixed cooldown after a slow confirmation.

## Understand delivery results

Records are grouped by date. Expand a row to see its evidence and, when available, the message ID.

| Result | Meaning |
| --- | --- |
| Server confirmed (`服务器确认`) | A send request started after the click received a successful server response. This does not establish delivery, reading or a streak update. |
| Page confirmed (`页面确认`) | A new matching outgoing message appeared and the editor cleared, but no server confirmation was captured. |
| Uncertain (`结果待确认`) | Dispatch may have occurred, but evidence was insufficient or the task was interrupted during sending. |
| Server rejected (`服务器拒绝`) | The server rejected the send. Sparky does not automatically retry. |
| Not sent / Cancelled (`未发送` / `已取消`) | The send was not triggered, or later work was cancelled. |

Receipts are associated using request timing in the current page; they are not an end-to-end delivery guarantee. Check page-only or uncertain results on your phone before deciding whether to resend manually. Interrupted sends are recorded rather than automatically replayed.

## Windows and startup

Settings are grouped into Account (`抖音账号`), General (`通用`) and Diagnostics (`诊断`); expand Run log (`运行日志`) to inspect or copy diagnostic logs.

The main window shows a Dock icon and supports ⌘Tab. Close it with the red close button or ⌘W to hide the Dock icon and keep the app in the menu bar. Open it again from the menu bar. Minimizing keeps the Dock icon.

To launch at login, first move Sparky into Applications, then enable the option in Settings. macOS may require approval in **System Settings → General → Login Items**. Quitting Sparky stops scheduling.

## Local data and privacy

Settings, account selections and up to **2,000 send metadata records** are stored in:

```text
~/Library/Application Support/Spark/state.json
```

The legacy directory and application identifier are retained for upgrade compatibility. The settings include the message template; individual history entries do not store an additional copy of the message body. The state file is writable and readable only by the current user. Login data is managed by WebKit; Sparky does not export login cookies or send data to a separate upload server.

Avatars download from supported Douyin/ByteDance HTTPS CDNs without login cookies, with restricted redirects. Only thumbnails are cached in:

```text
~/Library/Caches/Sparky/Avatars
```

The cache retains approximately the latest 512 thumbnails and refreshes them after 30 days. Unsupported URLs or failed downloads use a placeholder and do not block sending.

This app depends on Douyin's web chat. Page changes, verification or site restrictions can interrupt it. Keep account data, login cookies and private chat screenshots out of public issues.
