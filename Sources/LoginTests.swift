import AppKit

@MainActor
enum LoginTests {
    static func wait(_ message: String, until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(12))
        while !condition() {
            guard ContinuousClock.now < deadline else { throw PrototypeError.message("Timed out: \(message)") }
            try await Task.sleep(for: .milliseconds(25))
        }
    }
    static func run() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sparky-login-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LocalStore(directory: root)
        let accountA = AccountInfo(uid: "123456789", nickname: "账号 A", douyinID: "a")
        let accountB = AccountInfo(uid: "987654321", nickname: "同名账号", douyinID: "b")
        let a = Contact(id: "test-a", title: "联系人 A", group: false)
        let b = Contact(id: "test-b", title: "联系人 B", group: false)
        let missing = Contact(id: "missing", title: "折叠联系人", group: false)
        var legacy = SavedState()
        legacy.account = accountA; legacy.contacts = [a,b,missing]; legacy.selected = [a.id,missing.id]
        try store.save(legacy)
        let engine = try BrowserEngine(selfTest: true)
        let model = SparkyModel(store: store, engine: engine, testing: true)
        try SelfTests.check(model.saved.selectionsByAccount?[accountA.uid] == [a.id,missing.id], "upgrade migrates current account selections without a new schema requirement")
        try model.applyContacts([a,b], account: accountA)
        try SelfTests.check(model.saved.selected == [a.id] && model.saved.selectionsByAccount?[accountA.uid]?.contains(missing.id) == true, "partial scans restore available IDs without forgetting missing contacts")
        model.toggleContact(a.id)
        model.select([b], enabled: true)
        try model.applyContacts([a,b,missing], account: accountA)
        try SelfTests.check(model.saved.selected == [b.id,missing.id], "individual and bulk edits update remembered selections")
        model.setSchedule(true)
        try model.applyContacts([a,b], account: accountB)
        try SelfTests.check(model.saved.selected.isEmpty && !model.saved.plan.enabled, "a new UID cannot inherit another account's selections or armed plan")
        model.select([a], enabled: true)
        try model.applyContacts([a,b,missing], account: accountA)
        try SelfTests.check(model.saved.selected == [b.id,missing.id], "switching back restores only that account's preferences")
        model.select([a,b,missing], enabled: false)
        try model.applyContacts([a,b], account: accountB)
        try SelfTests.check(model.saved.selected == [a.id], "other accounts retain independent selections for shared contact IDs")
        try model.applyContacts([a,b,missing], account: accountA)
        try SelfTests.check(model.saved.selected.isEmpty, "an explicitly empty selection remains empty after switching back")
        model.select([a,b], enabled: true)
        await model.logout()
        try SelfTests.check(model.saved.account == nil && model.saved.selectionsByAccount?[accountA.uid] == [a.id,b.id], "logout retains account preferences while clearing the active session")
        let restored = SparkyModel(store: store, engine: engine, testing: true)
        try SelfTests.check(restored.saved.selectionsByAccount?[accountA.uid] == [a.id,b.id], "per-account preferences survive logout and application restart")

        // The fixture uses an isolated, nonpersistent WebKit store. Keep a
        // login overlay present even though a profile was already captured.
        try engine.start(show: false); _ = try await engine.accountInfo()
        _ = try await engine.evaluate("const login=document.createElement('div');login.setAttribute('data-e2e','login-container');document.body.appendChild(login);true")
        restored.connect()
        try await Task.sleep(for: .milliseconds(650))
        try SelfTests.check(restored.loginInProgress && restored.busy && engine.window?.isVisible == true && restored.saved.account == nil, "a captured profile alone does not dismiss an unfinished login")
        restored.refresh(); restored.connect()
        try SelfTests.check(restored.loginInProgress, "duplicate login and refresh requests do not start overlapping scans")
        let browserWindow = engine.window!
        _ = try await engine.evaluate("document.querySelector('[data-e2e=login-container]').remove();true")
        try await wait("login detection", until: { !restored.loginInProgress })
        try SelfTests.check(!browserWindow.isVisible && restored.busy, "successful login hides the chat window before background scanning")
        try await wait("automatic contact scan", until: { !restored.busy })
        try SelfTests.check(restored.notice == nil && restored.saved.account?.uid == accountA.uid && restored.saved.contacts.count == 2 && restored.saved.selected == [a.id,b.id], "login automatically scans contacts and restores the matching account selection")
        try SelfTests.check(engine.webView == nil && !restored.saved.plan.enabled && restored.saved.history.isEmpty, "login releases WebKit without enabling a plan or sending messages")

        try engine.start(show: false); _ = try await engine.accountInfo()
        _ = try await engine.evaluate("const login=document.createElement('div');login.setAttribute('data-e2e','login-container');document.body.appendChild(login);true")
        restored.connect()
        engine.window!.performClose(nil)
        try SelfTests.check(!restored.busy && !restored.loginInProgress && engine.webView == nil, "closing the login window cancels waiting and releases WebKit")
        restored.connect()
        try await wait("restart login after close", until: { !restored.busy })
        try SelfTests.check(restored.notice == nil && restored.saved.selected == [a.id,b.id], "a cancelled login task cannot tear down a newer login")
        restored.connect(); restored.cancelLogin()
        try await Task.sleep(for: .milliseconds(100))
        try SelfTests.check(!restored.busy && engine.webView == nil, "explicit cancellation finishes without an error or contact changes")

        try engine.start(show: false); _ = try await engine.accountInfo()
        _ = try await engine.evaluate("const login=document.createElement('div');login.setAttribute('data-e2e','login-container');document.body.appendChild(login);true")
        var timedOut = false
        do { _ = try await engine.waitForLogin(timeout: 0.1) } catch is CancellationError { throw CancellationError() } catch { timedOut = true }
        try SelfTests.check(timedOut && engine.window?.isVisible == false, "unfinished login has a bounded wait without reporting success")
        _ = try await engine.evaluate("document.querySelector('[data-e2e=login-container]').remove();setTimeout(()=>{window.__sparkPrototype.status().profile.uid='987654321'},150);true")
        var switched = false
        do { try await restored.synchronizeContacts(account: accountA) } catch { switched = true }
        try SelfTests.check(switched && restored.saved.account == nil && restored.saved.contacts.isEmpty && !restored.canRun && !restored.saved.plan.enabled, "an account change during scanning discards results and disables sending")
        engine.stop()
    }
}
