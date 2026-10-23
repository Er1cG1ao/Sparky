import AppKit
import WebKit
import Foundation

struct Contact: Hashable, Codable, Identifiable {
    let id: String
    let title: String
    let group: Bool
}

struct Delivery {
    let state: DeliveryState
    let detail: String
    var messageID: String = ""
}

enum PrototypeError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

@MainActor
final class BrowserEngine: NSObject, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    var webView: WKWebView?
    var window: NSWindow?
    var log: (String) -> Void = { _ in }
    var busy = false
    var draft: (id: String, text: String)?
    let selfTest: Bool
    let resourceURL: URL
    var selectors: [String: String] = [:]
    let fixtureURL: URL?

    init(selfTest: Bool = false) throws {
        self.selfTest = selfTest
        guard let resources = Bundle.main.resourceURL else { throw PrototypeError.message("缺少应用资源") }
        resourceURL = resources
        fixtureURL = selfTest ? resources.appendingPathComponent("Fixture.html") : nil
        let data = try Data(contentsOf: resources.appendingPathComponent("selectors.json"))
        selectors = (try JSONSerialization.jsonObject(with: data)) as? [String: String] ?? [:]
        super.init()
    }

    func start(show: Bool) throws {
        if let window = window { if show { window.makeKeyAndOrderFront(nil) }; return }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = selfTest ? .nonPersistent() : .default()
        if #available(macOS 14.0, *) { configuration.preferences.inactiveSchedulingPolicy = .none }
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        if selfTest {
            let mock = "window.fetch=async url=>String(url).includes('/message/send')?new Response(new Uint8Array(window.fixtureMode==='reject'?[24,8,34,2,78,79]:[24,0,34,2,79,75])):new Response(JSON.stringify({status_code:0,user:{nickname:'离线测试账号',unique_id:'offline-test',uid:'123456789'}}),{headers:{'content-type':'application/json'}});"
            configuration.userContentController.addUserScript(WKUserScript(source: mock, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        let script = try String(contentsOf: resourceURL.appendingPathComponent("Engine.js"), encoding: .utf8)
        configuration.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        // No native message handler is registered. Webpages cannot invoke native methods.
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 1120, height: 780), configuration: configuration)
        web.navigationDelegate = self
        web.uiDelegate = self
        web.allowsBackForwardNavigationGestures = false
        let browserWindow = NSWindow(contentRect: web.frame, styleMask: [.titled,.closable,.miniaturizable,.resizable], backing: .buffered, defer: false)
        browserWindow.title = "Sparky · 抖音登录"
        browserWindow.isReleasedWhenClosed = false
        browserWindow.delegate = self
        browserWindow.contentView = web
        browserWindow.center()
        webView = web
        window = browserWindow
        if show { browserWindow.makeKeyAndOrderFront(nil) }
        if let fixture = fixtureURL { web.loadFileURL(fixture, allowingReadAccessTo: resourceURL) }
        else { web.load(URLRequest(url: URL(string: "https://www.douyin.com/chat")!)) }
        log("已启动连接，正在恢复登录状态。")
    }

    func stop() {
        guard !busy else { log("操作进行中，请等本次操作结束后再释放引擎。"); return }
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
        webView = nil
        draft = nil
        log("已释放 WKWebView；WebKit 子进程的回收时间由系统决定，登录数据保留。")
    }

    func trustedURL(_ url: URL?) -> Bool {
        guard let url else { return false }
        if selfTest { return url.standardizedFileURL == fixtureURL?.standardizedFileURL }
        return url.scheme == "https" && url.host == "www.douyin.com" && (url.path == "/chat" || url.path.hasPrefix("/chat/"))
    }

    func evaluate(_ script: String) async throws -> Any? {
        guard let web = webView, trustedURL(web.url) else { throw PrototypeError.message("请先加载抖音聊天页，等待网页就绪。") }
        return try await withCheckedThrowingContinuation { continuation in
            web.evaluateJavaScript(script, in: nil, in: .page) { result in
                switch result {
                case .success(let value): continuation.resume(returning: value)
                case .failure(let error):
                    let info = (error as NSError).userInfo
                    if let detail = info["WKJavaScriptExceptionMessage"] as? String {
                        continuation.resume(throwing: PrototypeError.message("网页脚本：\(detail)"))
                    } else { continuation.resume(throwing: error) }
                }
            }
        }
    }

    func json(_ object: Any) throws -> String {
        String(data: try JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed,.sortedKeys]), encoding: .utf8)!
    }

    func call(_ method: String, _ args: [Any] = []) async throws -> Any? {
        let arguments = try args.map { try json($0) }.joined(separator: ",")
        let wrapped = "(() => { try { return {ok:true,value:window.__sparkPrototype.\(method)(\(arguments)) ?? null}; } catch(e) { return {ok:false,error:String(e.message || e)}; } })()"
        guard let result = try await evaluate(wrapped) as? [String: Any] else { throw PrototypeError.message("网页脚本没有返回有效结果：\(method)") }
        guard result["ok"] as? Bool == true else { throw PrototypeError.message("网页脚本：\(result["error"] as? String ?? "未知错误")") }
        let value = result["value"]
        return value is NSNull ? nil : value
    }

    func pause(_ seconds: Double) async throws { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }

    func waitUntilReady() async throws {
        for _ in 0..<60 {
            if let status = try? await call("status") as? [String: Any], status["chatReady"] as? Bool == true { return }
            try await pause(0.5)
        }
        throw PrototypeError.message("聊天页未就绪：请检查扫码登录、验证码或网页兼容性。")
    }

    func scan() async throws -> [Contact] {
        try await waitUntilReady()
        _ = try await call("scroll", [true])
        try await pause(0.4)
        var found: [String: Contact] = [:]
        var order: [String] = []
        var idle = 0
        for step in 0..<160 {
            guard let rows = try await call("rows") as? [[String: Any]] else { throw PrototypeError.message("会话脚本未返回列表") }
            let previous = found.count
            for row in rows {
                guard let id = row["id"] as? String, !id.isEmpty else { continue }
                if found[id] == nil { order.append(id) }
                found[id] = Contact(id: id, title: row["title"] as? String ?? id, group: row["group"] as? Bool ?? false)
            }
            let position = try await call("scroll") as? [String: Any] ?? [:]
            if position["found"] as? Bool != true { break }
            idle = found.count == previous && position["bottom"] as? Bool == true ? idle + 1 : 0
            if idle >= 5 { break }
            if step % 10 == 0 { log("已读取 \(found.count) 个会话…") }
            try await pause(0.4)
        }
        _ = try await call("scroll", [true])
        let contacts = order.compactMap { found[$0] }
        if contacts.isEmpty { throw PrototypeError.message("没有读取到带会话 ID 的联系人，请检查登录状态或网页是否已变化。") }
        log("已读取 \(contacts.count) 个会话。折叠/陌生人列表可能未包含在内。")
        return contacts
    }

    func select(_ contact: Contact) async throws {
        if let current = try await call("current") as? [String: Any], current["id"] as? String == contact.id { return }
        _ = try await call("scroll", [true])
        try await pause(0.3)
        var idle = 0
        for _ in 0..<160 {
            if try await call("select", [contact.id]) as? Bool == true {
                for _ in 0..<15 {
                    try await pause(0.15)
                    if let current = try await call("current") as? [String: Any], current["id"] as? String == contact.id { return }
                }
                throw PrototypeError.message("点击会话后身份未确认，已停止。可以在网页手动选中该联系人后重试。")
            }
            let position = try await call("scroll") as? [String: Any] ?? [:]
            idle = position["bottom"] as? Bool == true ? idle + 1 : 0
            if idle >= 5 { break }
            try await pause(0.3)
        }
        throw PrototypeError.message("找不到选定会话，请刷新联系人列表。")
    }

    func prepare(_ contact: Contact, text: String) async throws {
        draft = nil
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !text.contains("\n"), !text.contains("\r"), text.utf16.count <= 500 else {
            throw PrototypeError.message("请输入 1–500 个字符的单行消息。")
        }
        try await select(contact)
        try await pause(0.4)
        guard let state = try await call("inspectDraft", [contact.id,text]) as? [String: Any], state["exists"] as? Bool == true else { throw PrototypeError.message("找不到输入框") }
        if state["empty"] as? Bool == false && state["matches"] as? Bool == true {
            draft = (contact.id, text)
            log("已有相同草稿，会话和内容已重新核对；未重复写入，也未发送。")
            return
        }
        guard state["empty"] as? Bool == true else {
            throw PrototypeError.message("网页输入框已有草稿，请先在网页中处理。Sparky 不会覆盖现有草稿。")
        }
        guard let inputScript = selectors["JS_TYPE_LINE"] else { throw PrototypeError.message("缺少输入脚本") }
        let argument = try json(["text": text, "enter": false] as [String: Any])
        _ = try await evaluate("(\(inputScript))(\(argument))")
        try await pause(0.6)
        guard let after = try await call("inspectDraft", [contact.id,text]) as? [String: Any], after["matches"] as? Bool == true else {
            throw PrototypeError.message("WebKit 输入验证失败，未发送。可显示网页检查草稿。")
        }
        draft = (contact.id, text)
        log("草稿已写入并核对会话身份；尚未发送。")
    }

    func send(_ contact: Contact, text: String, beforeDispatch: () throws -> Void = {}) async throws -> Delivery {
        guard let prepared = draft, prepared.id == contact.id, prepared.text == text else {
            throw PrototypeError.message("请先为当前联系人和内容写入草稿，再点击发送。")
        }
        let inspection = try await call("inspectDraft", [contact.id, text]) as? [String: Any] ?? [:]
        guard inspection["matches"] as? Bool == true else { throw PrototypeError.message("草稿或收件人已变化，未点击发送。") }
        let button = try await call("sendDiagnostic") as? [String: Any] ?? [:]
        guard button["found"] as? Bool == true, button["disabled"] as? Bool != true else { throw PrototypeError.message("发送按钮尚未就绪，未点击发送。") }
        try beforeDispatch() // Persist dispatch intent before a potentially irreversible click.
        draft = nil
        guard let ticket = try await call("send", [contact.id, text]) as? [String: Any], ticket["token"] as? String != nil else {
            throw PrototypeError.message("发送按钮没有返回结果，请手动检查聊天记录，不要立即重试。")
        }
        var domSeen = false
        for _ in 0..<40 {
            try await pause(0.3)
            let proof = try await call("proof", [contact.id, text, ticket]) as? [String: Any] ?? [:]
            if proof["state"] as? String == "ack" { return Delivery(state: .confirmed, detail: "服务器已确认发送；不代表对方已读或火花已更新。", messageID: (proof["receipt"] as? [String: Any])?["messageID"] as? String ?? "") }
            if proof["state"] as? String == "rejected" { return Delivery(state: .rejected, detail: "服务器拒绝本次发送。不会自动重试。") }
            if proof["state"] as? String == "changed" { throw PrototypeError.message("发送后会话发生变化，结果待确认。不会自动重试。") }
            if proof["domSeen"] as? Bool == true { domSeen = true }
        }
        return Delivery(state: domSeen ? .pageOnly : .uncertain, detail: domSeen ? "页面出现新发出的对应消息，未捕获服务器回执。请用手机核实。" : "已执行发送，但未确认结果；不会自动重试。")
    }

    func accountInfo() async throws -> AccountInfo {
        try await waitUntilReady()
        for _ in 0..<20 {
            if let status = try await call("status") as? [String: Any], let profile = status["profile"] as? [String: Any], let uid = profile["uid"] as? String, !uid.isEmpty {
                return AccountInfo(uid: uid, nickname: profile["nickname"] as? String ?? "抖音账号", douyinID: profile["douyinID"] as? String ?? "")
            }
            try await pause(0.25)
        }
        throw PrototypeError.message("聊天页已加载，但暂未识别账号。请打开登录窗口检查，再刷新联系人。")
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !busy else { return false }
        stop(); return true
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { log("网页加载完成，可以检查账号、读取会话。") }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { draft = nil }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { log("网页加载失败：\(error.localizedDescription)") }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard navigationAction.targetFrame?.isMainFrame != false, let url = navigationAction.request.url else { decisionHandler(.allow); return }
        if selfTest { decisionHandler(url.isFileURL && url.standardizedFileURL == fixtureURL?.standardizedFileURL ? .allow : .cancel); return }
        let host = url.host?.lowercased() ?? ""
        let allowed = url.scheme == "https" && (host == "douyin.com" || host.hasSuffix(".douyin.com") || host == "douyin.com.cn" || host.hasSuffix(".douyin.com.cn"))
        decisionHandler(allowed ? .allow : .cancel)
        if !allowed { log("已阻止跳转到聊天站点以外的地址。") }
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        log("网页请求新窗口；Sparky 未开放弹窗。若扫码登录因此受阻，请反馈。")
        return nil
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { draft = nil; log("WebKit 内容进程已退出，请重新加载网页。") }
}

