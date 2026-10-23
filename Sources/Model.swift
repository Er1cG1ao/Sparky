import AppKit
import Combine
import Foundation
import ServiceManagement

enum DeliveryState: String, Codable {
    case queued, preparing, sending, confirmed, pageOnly, uncertain, rejected, failed, cancelled
    var label: String {
        switch self {
        case .queued: return "等待执行"
        case .preparing: return "准备中"
        case .sending: return "正在发送"
        case .confirmed: return "服务器确认"
        case .pageOnly: return "页面确认"
        case .uncertain: return "结果待确认"
        case .rejected: return "服务器拒绝"
        case .failed: return "未发送"
        case .cancelled: return "已取消"
        }
    }
    var unfinished: Bool { [.queued,.preparing,.sending].contains(self) }
}

struct AccountInfo: Codable, Equatable {
    var uid: String
    var nickname: String
    var douyinID: String
}
struct DailyPlan: Codable {
    var enabled = false
    var hour = 9
    var minute = 0
    var enabledSince: Date?
    var lastScheduledDay: String?
    func due(at now: Date, calendar: Calendar = .current) -> Date? {
        guard enabled, let armed = enabledSince,
              let time = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now),
              time >= armed, time <= now, lastScheduledDay != Self.day(now, calendar: calendar) else { return nil }
        return time
    }
    func next(at now: Date, calendar: Calendar = .current) -> Date? {
        guard enabled, let armed = enabledSince,
              let today = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) else { return nil }
        if lastScheduledDay != Self.day(now,calendar: calendar), today >= armed { return max(today, now) }
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) else { return nil }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: tomorrow)
    }
    static func day(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year,.month,.day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
struct SendRecord: Codable, Identifiable {
    var id = UUID()
    var runID: UUID
    var contactID: String
    var name: String
    var accountUID: String
    var date: Date
    var finished: Date?
    var scheduled: Bool
    var state: DeliveryState
    var detail: String
    var messageID = ""
}
struct SavedState: Codable {
    var version = 1
    var account: AccountInfo?
    var contacts: [Contact] = []
    var selected: Set<String> = []
    var message = "续火花 🔥"
    var plan = DailyPlan()
    var history: [SendRecord] = []
}

final class LocalStore {
    let directory: URL
    let file: URL
    init(directory: URL) { self.directory = directory; file = directory.appendingPathComponent("state.json") }
    func load() throws -> SavedState {
        guard FileManager.default.fileExists(atPath: file.path) else { return SavedState() }
        return try JSONDecoder().decode(SavedState.self, from: Data(contentsOf: file))
    }
    func save(_ state: SavedState) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(state).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
    func preserveBrokenFile() {
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        try? FileManager.default.copyItem(at: file, to: directory.appendingPathComponent("recovery-\(UUID().uuidString).json"))
    }
}

@MainActor
final class SparkyModel: ObservableObject {
    @Published private(set) var saved: SavedState
    @Published var busy = false
    @Published var engineActive = false
    @Published var progress = 0
    @Published var total = 0
    @Published var activity = "一切就绪"
    @Published var notice: String?
    @Published var logs: [String] = []
    @Published var loginEnabled = false
    @Published var now = Date()
    let engine: BrowserEngine
    let store: LocalStore
    var changed: (() -> Void)?
    var confirmSend: (() -> Void)?
    var timer: Timer?
    var wakeObserver: NSObjectProtocol?
    @Published var cancelRequested = false
    let testing: Bool

    init(store: LocalStore, engine: BrowserEngine, testing: Bool = false) {
        self.store = store; self.engine = engine; self.testing = testing
        do { saved = try store.load() }
        catch { store.preserveBrokenFile(); saved = SavedState(); notice = "配置读取失败，已保留恢复副本，定时发送保持关闭。" }
        for i in saved.history.indices where saved.history[i].state.unfinished {
            let dispatched = saved.history[i].state == .sending
            saved.history[i].state = dispatched ? .uncertain : .failed
            saved.history[i].detail = dispatched ? "上次退出发生在发送阶段，可能已发出；不自动重试。" : "上次任务中断，尚未触发发送。"
            saved.history[i].finished = Date()
        }
        engine.log = { [weak self] text in self?.log(text) }
        if !testing {
            loginEnabled = SMAppService.mainApp.status == .enabled
            timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.tick() } }
            try? store.save(saved)
        }
    }
    var selectedContacts: [Contact] { saved.contacts.filter { saved.selected.contains($0.id) } }
    var messageValid: Bool {
        let s = saved.message.trimmingCharacters(in: .whitespacesAndNewlines)
        return !s.isEmpty && !s.contains("\n") && !s.contains("\r") && saved.message.utf16.count <= 500
    }
    var canRun: Bool { saved.account != nil && !selectedContacts.isEmpty && messageValid }
    var nextRun: Date? { canRun ? saved.plan.next(at: now) : nil }
    var todayRecords: [SendRecord] { saved.history.filter { Calendar.current.isDateInToday($0.date) } }
    var todayConfirmed: Int { todayRecords.filter { $0.state == .confirmed }.count }
    var todayAttention: Int { todayRecords.filter { [.uncertain,.rejected,.failed].contains($0.state) }.count }
    func log(_ text: String) {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "HH:mm:ss"
        logs.append("\(f.string(from: Date()))  \(text)")
        logs = Array(logs.suffix(200))
    }
    func commit(_ change: (inout SavedState) -> Void) throws {
        var copy = saved; change(&copy)
        copy.history = Array(copy.history.suffix(2000))
        try store.save(copy)
        saved = copy
        changed?()
    }
    func edit(_ change: (inout SavedState) -> Void) {
        guard !busy else { return }
        do { try commit(change) } catch { notice = "无法保存设置：\(error.localizedDescription)" }
    }
    func toggleContact(_ id: String) { edit { if $0.selected.contains(id) { $0.selected.remove(id) } else { $0.selected.insert(id) } } }
    func select(_ contacts: [Contact], enabled: Bool) { edit { state in for c in contacts { if enabled { state.selected.insert(c.id) } else { state.selected.remove(c.id) } } } }
    func setSchedule(_ enabled: Bool) {
        guard !busy else { return }
        if enabled && !canRun { notice = "请先连接账号、选择联系人，并填写一条有效消息。"; return }
        edit { $0.plan.enabled = enabled; if enabled { $0.plan.enabledSince = Date() } }
        now = Date(); changed?()
    }
    func setTime(_ date: Date) {
        let c = Calendar.current.dateComponents([.hour,.minute], from: date)
        edit { $0.plan.hour = c.hour ?? 9; $0.plan.minute = c.minute ?? 0; if $0.plan.enabled { $0.plan.enabledSince = Date() } }
    }
    var timeDate: Date { Calendar.current.date(bySettingHour: saved.plan.hour, minute: saved.plan.minute, second: 0, of: now) ?? now }
    func tick(at date: Date = Date()) {
        engineActive = engine.webView != nil
        now = date; changed?()
        guard !busy, canRun, saved.plan.due(at: date) != nil else { return }
        Task { await runBatch(scheduled: true) }
    }
    func connect() {
        guard !busy else { return }
        do { try engine.start(show: true); engineActive = true; log("完成登录后，点击刷新联系人。") }
        catch { notice = error.localizedDescription }
    }
    func refresh() {
        guard !busy else { return }
        busy = true; activity = "正在刷新联系人…"
        Task {
            defer { busy = false; engine.stop(); engineActive = false; activity = "一切就绪"; changed?() }
            do {
                try engine.start(show: false); engineActive = true
                let account = try await engine.accountInfo()
                let contacts = try await engine.scan()
                try commit { state in
                    if state.account?.uid != account.uid { state.selected = []; state.plan.enabled = false; state.plan.lastScheduledDay = nil }
                    state.account = account; state.contacts = contacts
                    state.selected.formIntersection(Set(contacts.map(\.id)))
                }
                log("联系人已更新：\(contacts.count) 个会话。")
            } catch { notice = error.localizedDescription; log("刷新失败：\(error.localizedDescription)") }
        }
    }
    func releaseEngine() {
        guard !busy else { return }
        engine.stop(); engineActive = false
    }
    func setLoginItem(_ enabled: Bool) {
        guard !testing else { return }
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            if enabled && !loginEnabled { notice = "请在系统设置 → 通用 → 登录项中批准 Sparky。" }
        } catch { notice = "登录启动设置未完成。请先将 Sparky.app 放入应用程序，再重试。\n\(error.localizedDescription)" }
    }
    func updateRecord(_ id: UUID, state: DeliveryState, detail: String, messageID: String = "") throws {
        try commit { data in
            guard let index = data.history.firstIndex(where: { $0.id == id }) else { return }
            data.history[index].state = state; data.history[index].detail = detail
            data.history[index].messageID = messageID
            if !state.unfinished { data.history[index].finished = Date() }
        }
    }
    func runBatch(scheduled: Bool) async {
        guard !busy else { return }
        if scheduled && saved.plan.due(at: Date()) == nil { return }
        guard canRun, let account = saved.account else { notice = "请先连接账号、选择联系人并填写消息。"; return }
        let targets = selectedContacts, text = saved.message, runID = UUID(), start = Date()
        let records = targets.map { SendRecord(runID: runID, contactID: $0.id, name: $0.title, accountUID: account.uid, date: start, scheduled: scheduled, state: .queued, detail: "等待执行") }
        do {
            // Claim today's run durably before starting WebKit. A restart must
            // never replay a partially executed scheduled batch.
            try commit { $0.plan.lastScheduledDay = DailyPlan.day(start); $0.history.append(contentsOf: records) }
        } catch { notice = "无法保存任务记录，未启动发送：\(error.localizedDescription)"; return }
        busy = true; engine.busy = true; cancelRequested = false; progress = 0; total = targets.count
        activity = "正在连接抖音…"; changed?()
        var fatal: String?
        defer {
            engine.busy = false; engine.stop(); engineActive = false; busy = false
            let run = saved.history.filter { $0.runID == runID }
            let confirmed = run.filter { $0.state == .confirmed }.count
            let page = run.filter { $0.state == .pageOnly }.count
            activity = cancelRequested ? "任务已停止" : "本次任务已结束"
            log("任务结束：服务器确认 \(confirmed)，页面确认 \(page)，其他 \(run.count-confirmed-page)。")
            changed?()
        }
        do {
            try engine.start(show: false); engineActive = true; engine.window?.orderOut(nil)
            let actual = try await engine.accountInfo()
            guard actual.uid == account.uid else { throw PrototypeError.message("当前登录账号与计划账号不一致。请刷新联系人后重新配置。") }
            for (index, contact) in targets.enumerated() {
                if cancelRequested { break }
                let record = records[index]
                activity = "\(index+1)/\(targets.count) · \(contact.title)"
                var dispatched = false
                let contactStart = ContinuousClock.now
                do {
                    try updateRecord(record.id, state: .preparing, detail: "正在定位联系人、核对草稿")
                    try await engine.prepare(contact, text: text)
                    let preparedAt=ContinuousClock.now
                    var dispatchAt=preparedAt
                    if cancelRequested { break }
                    let result = try await engine.send(contact, text: text, beforeDispatch: {
                        try self.updateRecord(record.id, state: .sending, detail: "已记录发送意图，正在触发一次发送")
                        dispatched = true
                        dispatchAt = .now
                    })
                    try updateRecord(record.id, state: result.state, detail: result.detail, messageID: result.messageID)
                    func seconds(_ duration:Duration) -> String {
                        let c=duration.components
                        return String(format:"%.2f",Double(c.seconds)+Double(c.attoseconds)/1e18)
                    }
                    log("\(result.state.label) · 准备 \(seconds(contactStart.duration(to:preparedAt)))s · 排队 \(seconds(preparedAt.duration(to:dispatchAt)))s · 回执 \(seconds(dispatchAt.duration(to:.now)))s")
                } catch {
                    do { try updateRecord(record.id, state: dispatched ? .uncertain : .failed, detail: error.localizedDescription) }
                    catch { throw PrototypeError.message("记录写入失败，已停止后续发送。请检查磁盘权限和历史记录。") }
                }
                progress = index + 1
                // The engine spaces actual dispatches; slow confirmations do not incur an extra cooldown.
            }
        } catch { fatal = error.localizedDescription; notice = fatal; log("任务中断：\(fatal!)") }
        do {
            try commit { state in
                for i in state.history.indices where state.history[i].runID == runID && state.history[i].state.unfinished {
                    state.history[i].state = state.history[i].state == .sending ? .uncertain : (cancelRequested ? .cancelled : .failed)
                    state.history[i].detail = fatal ?? (cancelRequested ? "用户停止了后续发送" : "任务未完成")
                    state.history[i].finished = Date()
                }
            }
        } catch { notice = "任务记录保存失败；已触发的消息请手动核实。" }
    }
    func clearHistory() { guard !busy else { return }; edit { $0.history.removeAll() } }
    func seedPreview() {
        saved.account = AccountInfo(uid: "demo", nickname: "演示账号", douyinID: "仅界面预览")
        saved.contacts = [Contact(id:"a",title:"清风",group:false),Contact(id:"b",title:"小林",group:false),Contact(id:"c",title:"周末搭子",group:true),Contact(id:"d",title:"许同学",group:false)]
        saved.selected = ["a","b","c"]
        saved.plan.hour = 21; saved.plan.minute = 30; saved.plan.enabled = true; saved.plan.enabledSince = Calendar.current.startOfDay(for: Date())
        saved.history = [SendRecord(runID:UUID(),contactID:"a",name:"清风",accountUID:"demo",date:Date(),finished:Date(),scheduled:true,state:.confirmed,detail:"服务器已确认发送。"),SendRecord(runID:UUID(),contactID:"b",name:"小林",accountUID:"demo",date:Date(),finished:Date(),scheduled:true,state:.pageOnly,detail:"页面已显示对应消息，未获取服务器回执。")]
    }
}
