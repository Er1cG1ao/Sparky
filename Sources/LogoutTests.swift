import AppKit
import WebKit

@MainActor
enum LogoutTests {
    static func cookies(_ store:WKWebsiteDataStore) async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in store.httpCookieStore.getAllCookies { continuation.resume(returning:$0) } }
    }
    static func setCookie(_ store:WKWebsiteDataStore) async {
        let cookie=HTTPCookie(properties:[.domain:".douyin.com",.path:"/",.name:"sessionid",.value:"offline-test-session",.secure:"TRUE"])!
        await withCheckedContinuation { (continuation:CheckedContinuation<Void,Never>) in
            store.httpCookieStore.setCookie(cookie) { continuation.resume() }
        }
    }
    static func run() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("sparky-logout-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at:root) }
        let oldJSON=Data("{\"version\":1,\"contacts\":[],\"selected\":[],\"message\":\"旧模板\",\"plan\":{\"enabled\":false,\"hour\":9,\"minute\":0},\"history\":[]}".utf8)
        let legacy=try JSONDecoder().decode(SavedState.self,from:oldJSON)
        try SelfTests.check(legacy.logoutPending == nil,"old configurations remain compatible with logout recovery")
        let engine=try BrowserEngine(selfTest:true)
        let store=LocalStore(directory:root.appendingPathComponent("state"))
        let model=SparkyModel(store:store,engine:engine,testing:true)
        try engine.start(show:false); let account=try await engine.accountInfo()
        let webStore=engine.webView!.configuration.websiteDataStore
        try SelfTests.check(!webStore.isPersistent,"logout tests use a nonpersistent website store")
        await setCookie(webStore)
        let before=await cookies(webStore)
        try SelfTests.check(before.contains{$0.name == "sessionid"},"offline login cookie is present before logout")
        let contact=Contact(id:"test-a",title:"离线联系人",group:false)
        try await engine.prepare(contact,text:"保留模板")
        try model.commit { state in
            state.account=account; state.contacts=[contact]; state.selected=[contact.id]; state.message="保留模板"
            state.plan.enabled=true; state.plan.enabledSince=Date()
            state.history=[SendRecord(runID:UUID(),contactID:contact.id,name:contact.title,accountUID:account.uid,date:Date(),scheduled:false,state:.confirmed,detail:"离线历史")]
        }
        model.busy=true; await model.logout(); model.busy=false
        let whileBusy=await cookies(webStore)
        try SelfTests.check(model.saved.account != nil && !whileBusy.isEmpty,"logout cannot interrupt an active operation")
        await model.logout()
        let after=await cookies(webStore)
        try SelfTests.check(after.isEmpty && engine.webView == nil && engine.draft == nil,"logout clears cookies and releases the page and draft")
        try SelfTests.check(model.saved.account == nil && model.saved.contacts.isEmpty && model.saved.selected.isEmpty,"logout clears the cached account, contacts and selections")
        try SelfTests.check(!model.saved.plan.enabled && !model.canRun && model.saved.logoutPending == nil,"successful logout pauses the plan and completes its journal")
        let persisted=try store.load()
        try SelfTests.check(persisted.message == "保留模板" && persisted.history.count == 1 && persisted.account == nil,"logout preserves message and history on disk")
        await model.logout()
        try SelfTests.check(model.saved.history.count == 1 && !model.busy,"repeated logout is harmless")

        var interrupted=persisted
        interrupted.logoutPending=true; interrupted.account=account; interrupted.contacts=[contact]; interrupted.selected=[contact.id]; interrupted.plan.enabled=true
        try store.save(interrupted)
        let recovery=SparkyModel(store:store,engine:try BrowserEngine(selfTest:true),testing:true)
        recovery.connect()
        try SelfTests.check(recovery.saved.account == nil && !recovery.saved.plan.enabled && !recovery.canRun && recovery.engine.webView == nil,"interrupted logout prevents reconnection and scheduled sending")
        await recovery.logout()
        try SelfTests.check(try store.load().logoutPending == nil,"interrupted logout can be resumed and completed")

        let blocked=root.appendingPathComponent("not-a-directory")
        try Data([0]).write(to:blocked)
        let failureEngine=try BrowserEngine(selfTest:true)
        let failure=SparkyModel(store:LocalStore(directory:blocked),engine:failureEngine,testing:true)
        failure.seedPreview()
        try failureEngine.start(show:false); _ = try await failureEngine.accountInfo()
        let failureStore=failureEngine.webView!.configuration.websiteDataStore
        await setCookie(failureStore)
        await failure.logout()
        let stillPresent=await cookies(failureStore)
        try SelfTests.check(failure.notice != nil && failure.saved.account != nil && !stillPresent.isEmpty,"persistence failure aborts logout before deleting login data")
        failureEngine.stop()
    }
}
