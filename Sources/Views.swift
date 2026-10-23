import SwiftUI
import AppKit

func displayDate(_ date:Date,withDay:Bool=false) -> String {
    let formatter=DateFormatter(); formatter.locale=Locale(identifier:"zh_CN")
    formatter.dateFormat=withDay ? "M月d日 HH:mm" : "HH:mm"
    return formatter.string(from:date)
}

private typealias ViewState<Value> = SwiftUI.State<Value>

private enum Page: String, CaseIterable, Identifiable {
    case plan = "发送计划", contacts = "联系人", history = "发送记录", settings = "设置"
    var id: String { rawValue }
    var icon: String { switch self { case .plan: return "paperplane"; case .contacts: return "person.2"; case .history: return "clock.arrow.circlepath"; case .settings: return "gearshape" } }
}

@MainActor
struct SparkyView: View {
    @ObservedObject var model: SparkyModel
    @ViewState private var page: Page? = .plan
    @ViewState private var search = ""
    @ViewState private var review = false
    @ViewState private var clearing = false
    @ViewState private var loggingOut = false
    init(model:SparkyModel) {
        self.model=model
        let initial: Page = CommandLine.arguments.contains("--ui-contacts") ? .contacts : CommandLine.arguments.contains("--ui-history") ? .history : CommandLine.arguments.contains("--ui-settings") ? .settings : .plan
        self._page=ViewState(initialValue:initial)
    }
    private var filtered: [Contact] { model.saved.contacts.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) } }
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 11) {
                    Image(systemName: "flame.fill").font(.system(size: 24)).foregroundStyle(.white).frame(width: 44,height: 44).background(.orange.gradient,in:RoundedRectangle(cornerRadius:12))
                    VStack(alignment:.leading,spacing:3) { Text("Sparky").font(.title2.bold()); Text("让联系，持续发生").font(.caption).foregroundStyle(.secondary) }
                }.padding(.horizontal,18).padding(.top,25)
                VStack(spacing:5) { ForEach(Page.allCases) { item in
                    Button { page = item } label: { HStack(spacing:10) { Image(systemName:item.icon).frame(width:21); Text(item.rawValue); Spacer() }.font(.body.weight(page == item ? .semibold : .regular)).padding(.horizontal,13).padding(.vertical,11).foregroundStyle(page == item ? Color.orange : Color.primary).background(page == item ? Color.orange.opacity(0.12) : Color.clear,in:RoundedRectangle(cornerRadius:9)).contentShape(RoundedRectangle(cornerRadius:9)) }.buttonStyle(.plain).accessibilityIdentifier("sidebar.\(item.rawValue)")
                } }.padding(.horizontal,12)
                Spacer()
                VStack(alignment:.leading,spacing:8) {
                    HStack { Circle().fill(model.busy ? .orange : .green).frame(width:7,height:7); Text(model.busy ? "任务进行中" : "菜单栏中待命").font(.caption) }
                    HStack(spacing:8) {
                        Text(model.saved.account?.nickname ?? "尚未连接账号").font(.subheadline.weight(.medium)).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength:0)
                        if model.loginInProgress {
                            Button("取消登录") { model.cancelLogin() }.font(.caption).buttonStyle(.plain).foregroundStyle(.secondary)
                        } else if model.saved.account != nil || model.saved.logoutPending == true {
                            Button { loggingOut = true } label: { Label("退出登录",systemImage:"rectangle.portrait.and.arrow.right").font(.caption) }.buttonStyle(.plain).foregroundStyle(.secondary).disabled(model.busy).help("退出本应用的抖音登录").accessibilityIdentifier("account.logout.sidebar")
                        } else {
                            Button("登录") { model.connect() }.font(.caption).buttonStyle(.plain).foregroundStyle(.orange).disabled(model.busy)
                        }
                    }
                    Text(model.engineActive ? "WebKit 已启动" : "引擎休眠 · 按需启动").font(.caption).foregroundStyle(.secondary)
                }.padding(18)
            }.navigationSplitViewColumnWidth(min:210,ideal:225,max:245)
        } detail: {
            VStack(spacing:0) {
                HStack {
                    VStack(alignment:.leading,spacing:5) { Text((page ?? .plan).rawValue).font(.largeTitle.bold()).accessibilityIdentifier("page.title"); Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
                    Spacer()
                    if page == .contacts { Button { model.refresh() } label: { Label("刷新",systemImage:"arrow.clockwise") }.disabled(model.busy) }
                }.padding(.horizontal,30).padding(.top,28).padding(.bottom,24)
                if model.busy {
                    VStack(alignment:.leading,spacing:8) { HStack { Text(model.activity).font(.callout); Spacer(); if model.engine.busy { Button(model.cancelRequested ? "正在停止…" : "停止后续发送") { model.cancelRequested = true }.disabled(model.cancelRequested) } }; if model.engine.busy { ProgressView(value:Double(model.progress),total:Double(max(1,model.total))) } else { ProgressView().controlSize(.small) } }.padding(.horizontal,30).padding(.bottom,20)
                }
                ScrollView {
                    LazyVStack(alignment:.leading,spacing:20) {
                        switch page ?? .plan { case .plan: plan; case .contacts: contacts; case .history: history; case .settings: settings }
                    }.padding(.horizontal,30).padding(.bottom,30)
                }
            }.background(Color(nsColor:.windowBackgroundColor))
        }.frame(minWidth:880,minHeight:640).tint(.orange).environment(\.locale,Locale(identifier:"zh_CN"))
        .onAppear { model.confirmSend = { page = .plan; review = true } }
        .sheet(isPresented:$review) { reviewSheet }
        .alert("操作未完成",isPresented:Binding(get:{model.notice != nil},set:{if !$0 { model.notice = nil }})) { Button("好",role:.cancel) { model.notice = nil } } message: { Text(model.notice ?? "") }
        .confirmationDialog(loggingOut ? "退出抖音登录？" : "清空所有发送记录？",isPresented:Binding(get:{loggingOut || clearing},set:{ if !$0 { loggingOut=false; clearing=false } }),titleVisibility:.visible) {
            if loggingOut {
                Button("退出登录",role:.destructive) { Task { await model.logout() } }.disabled(model.busy)
            } else {
                Button("清空记录",role:.destructive) { model.clearHistory() }
            }
            Button("取消",role:.cancel) { }
        } message: {
            Text(loggingOut ? "将暂停定时计划并清空当前联系人，保留各账号的好友选择、消息模板与发送记录。仅退出本应用，不影响手机或 Safari。" : "这不会重置今天的定时任务，也不会重新发送。")
        }
    }
    private var subtitle: String {
        switch page ?? .plan { case .plan: return "一条消息，一份每天的惦记。"; case .contacts: return "选择要保持联系的人，也支持群聊。"; case .history: return "每位联系人的发送结果，都在这里。"; case .settings: return "账号、启动方式与运行状态。" }
    }
    private func card<Content:View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment:.leading,spacing:16,content:content).padding(22).frame(maxWidth:.infinity,alignment:.leading).background(Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:16)).overlay(RoundedRectangle(cornerRadius:16).stroke(.primary.opacity(0.055),lineWidth:1))
    }
    private func stat(_ title:String,_ value:String,_ icon:String,_ color:Color) -> some View {
        VStack(alignment:.leading,spacing:14) { Image(systemName:icon).foregroundStyle(color).font(.title3); Text(value).font(.system(size:25,weight:.semibold,design:.rounded)); Text(title).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth:.infinity,alignment:.leading).padding(20).background(Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:15))
    }
    private var plan: some View {
        Group {
            HStack(spacing:12) { stat("已选联系人",String(model.selectedContacts.count),"person.2.fill",.orange); stat("今日服务器确认",String(model.todayConfirmed),"checkmark.circle.fill",.green); stat("下次发送",model.nextRun.map { displayDate($0) } ?? "未开启","clock.fill",.blue) }
            card {
                Label("发送内容",systemImage:"text.bubble").font(.headline)
                TextField("写一句想发的话…",text:Binding(get:{model.saved.message},set:{v in model.edit { $0.message = v }})).textFieldStyle(.plain).font(.title3).padding(15).background(Color(nsColor:.textBackgroundColor),in:RoundedRectangle(cornerRadius:10)).disabled(model.busy)
                HStack { Text("单行消息，最多 500 个字符").foregroundStyle(model.messageValid ? Color.secondary : .red); Spacer(); Text("\(model.saved.message.utf16.count)/500").monospacedDigit().foregroundStyle(.secondary) }.font(.caption)
            }
            card {
                HStack { Label("每日定时",systemImage:"clock").font(.headline); Spacer(); Toggle("开启定时",isOn:Binding(get:{model.saved.plan.enabled},set:{model.setSchedule($0)})).labelsHidden().toggleStyle(.switch).disabled(model.busy) }
                HStack(alignment:.center) {
                    DatePicker("每天",selection:Binding(get:{model.timeDate},set:{model.setTime($0)}),displayedComponents:.hourAndMinute).datePickerStyle(.field).fixedSize().disabled(model.busy)
                    Spacer()
                    VStack(alignment:.trailing,spacing:5) { Text(model.nextRun.map { "下次 · " + displayDate($0,withDay:true) } ?? "定时发送尚未开启").font(.callout.weight(.medium)); Text(TimeZone.current.localizedName(for:.standard,locale:Locale(identifier:"zh_CN")) ?? TimeZone.current.identifier).font(.caption).foregroundStyle(.secondary) }
                }
                Text("请保持 Sparky 在菜单栏运行。电脑休眠期间不发送，唤醒后只补当日任务；开启时已错过的时间从明天开始。").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }
            card {
                HStack { Label("接收人",systemImage:"person.2").font(.headline); Spacer(); Button("管理联系人") { page = .contacts } }
                if model.selectedContacts.isEmpty { Text("先连接抖音，刷新联系人，再勾选要发送的对象。").foregroundStyle(.secondary).font(.callout) }
                else { Text(model.selectedContacts.map(\.title).joined(separator:"、")).font(.callout).lineLimit(3) }
            }
            HStack { Text(model.busy ? model.activity : "发送后会逐人核实结果，不自动重试。").font(.caption).foregroundStyle(.secondary); Spacer(); Button { review = true } label: { Label("立即执行…",systemImage:"paperplane.fill") }.buttonStyle(.borderedProminent).controlSize(.large).disabled(!model.canRun || model.busy) }
        }
    }
    private var contacts: some View {
        Group {
            HStack { TextField("搜索联系人或群聊",text:$search).textFieldStyle(.roundedBorder); Text("已选 \(model.selectedContacts.count)").foregroundStyle(.secondary).font(.callout) }
            HStack { Button("全选搜索结果") { model.select(filtered,enabled:true) }; Button("取消选择") { model.select(filtered,enabled:false) }; Spacer(); Text("\(filtered.count) 个会话").font(.caption).foregroundStyle(.secondary) }.disabled(model.busy)
            if model.saved.contacts.isEmpty {
                card { Image(systemName:"person.crop.circle.badge.plus").font(.system(size:36)).foregroundStyle(.orange); Text("先连接你的抖音账号").font(.title3.bold()); Text("在系统 WebKit 窗口完成登录，然后刷新联系人。列表来自已有聊天会话，折叠及陌生人会话可能不包含在内。").font(.callout).foregroundStyle(.secondary); HStack { Button("打开登录窗口") { model.connect() }; Button("刷新联系人") { model.refresh() } }.disabled(model.busy) }
            } else {
                LazyVStack(spacing:1) { ForEach(filtered) { contact in
                    Toggle(isOn:Binding(get:{model.saved.selected.contains(contact.id)},set:{_ in model.toggleContact(contact.id)})) {
                        HStack(spacing:13) { avatar(contact); VStack(alignment:.leading,spacing:4) { Text(contact.title).font(.body.weight(.medium)); Text(contact.group ? "群聊" : "私聊").font(.caption).foregroundStyle(.secondary) }; Spacer() }.padding(.vertical,9)
                    }.toggleStyle(.checkbox).padding(.horizontal,18).disabled(model.busy)
                    Divider().padding(.leading,65)
                } }.padding(.vertical,8).background(Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:14))
            }
        }
    }
    private func avatar(_ c:Contact) -> some View { ContactAvatar(contact:c) }
    private var history: some View {
        Group {
            HStack { Text("保留最近 2,000 条记录").font(.caption).foregroundStyle(.secondary); Spacer(); Button("清空…") { clearing = true }.disabled(model.busy || model.saved.history.isEmpty) }
            if model.saved.history.isEmpty { card { Label("还没有发送记录",systemImage:"tray").font(.headline); Text("执行一次任务后，这里会显示每个人的结果。").font(.callout).foregroundStyle(.secondary) } }
            ForEach(model.saved.history.reversed()) { r in
                card {
                    HStack { VStack(alignment:.leading,spacing:5) { Text(r.name).font(.headline); Text(displayDate(r.date,withDay:true) + (r.scheduled ? " · 定时发送" : " · 手动执行")).font(.caption).foregroundStyle(.secondary) }; Spacer(); Label(r.state.label,systemImage:r.state == .confirmed ? "checkmark.circle.fill" : "info.circle").font(.callout).foregroundStyle(r.state == .confirmed ? .green : r.state == .pageOnly ? .blue : .orange) }
                    Text(r.detail).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    if !r.messageID.isEmpty { Text("消息 ID · \(r.messageID)").font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled) }
                }
            }
            Text("服务器确认代表发送接口成功回执，不代表对方已读或火花已更新。“页面确认”和“结果待确认”请用手机核实后再决定是否重发。").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var settings: some View {
        Group {
            card { Label("抖音账号",systemImage:"person.crop.circle").font(.headline); Text(model.saved.account?.nickname ?? "尚未连接").font(.title3.weight(.medium)); if let a = model.saved.account { Text("抖音号 · \(a.douyinID)").font(.caption).foregroundStyle(.secondary) }; HStack { Button("打开登录窗口") { model.connect() }; Button("刷新账号与联系人") { model.refresh() }; Button("退出登录",role:.destructive) { loggingOut = true }.accessibilityIdentifier("account.logout.settings") }.disabled(model.busy); if model.loginInProgress { Button("取消登录") { model.cancelLogin() } }; Text("登录后自动收起窗口并读取联系人，按账号恢复已选会话。切换账号或退出登录后需手动开启定时计划。").font(.caption).foregroundStyle(.secondary) }
            card { Toggle("登录 Mac 时启动 Sparky",isOn:Binding(get:{model.loginEnabled},set:{model.setLoginItem($0)})); Text("先将应用移入“应用程序”。可在系统设置的“登录项”中管理。").font(.caption).foregroundStyle(.secondary) }
            card { HStack { Label("运行状态",systemImage:"waveform.path").font(.headline); Spacer(); Text(model.engineActive ? "引擎已启动" : "引擎休眠").foregroundStyle(.secondary) }; Text("使用 macOS 自带 WebKit；任务结束后释放网页，登录状态保留。").font(.callout).foregroundStyle(.secondary); Button("释放当前引擎") { model.releaseEngine() }.disabled(model.busy || !model.engineActive) }
            card { HStack { Text("运行日志").font(.headline); Spacer(); Button("复制日志") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(model.logs.joined(separator:"\n"),forType:.string) } }; Text(model.logs.suffix(10).joined(separator:"\n").isEmpty ? "暂无日志" : model.logs.suffix(10).joined(separator:"\n")).font(.system(size:11,design:.monospaced)).foregroundStyle(.secondary).textSelection(.enabled) }
            Text("Sparky 0.2.5 · macOS 原生界面\n设置与记录保存在本机；登录数据由系统 WebKit 管理。").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var reviewSheet: some View {
        VStack(alignment:.leading,spacing:20) {
            Image(systemName:"paperplane.circle.fill").font(.system(size:40)).foregroundStyle(.orange)
            Text("发送给 \(model.selectedContacts.count) 个会话").font(.title2.bold())
            Text(model.saved.message).font(.title3).textSelection(.enabled)
            ScrollView { Text(model.selectedContacts.map(\.title).joined(separator:"、")).frame(maxWidth:.infinity,alignment:.leading).foregroundStyle(.secondary) }.frame(maxHeight:110)
            Text("将逐个发送，每个会话触发一次。本次执行也计入今日计划，今天不会再自动发送。").font(.callout).foregroundStyle(.secondary)
            HStack { Spacer(); Button("取消") { review = false }.keyboardShortcut(.cancelAction); Button("确认发送") { review = false; Task { await model.runBatch(scheduled:false) } }.buttonStyle(.borderedProminent).disabled(!model.canRun || model.busy) }
        }.padding(30).frame(width:440)
    }
}
