import SwiftUI
import AppKit

func displayDate(_ date: Date, withDay: Bool = false) -> String {
    let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = withDay ? "M月d日 HH:mm" : "HH:mm"
    return formatter.string(from: date)
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
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState private var sidebarCollapsed = false
    @ViewState private var page: Page? = .plan
    @ViewState private var search = ""
    @ViewState private var selectedOnly = false
    @ViewState private var review = false
    @ViewState private var clearing = false
    @ViewState private var loggingOut = false
    init(model: SparkyModel) {
        self.model = model
        self._sidebarCollapsed = ViewState(initialValue: model.testing
            ? CommandLine.arguments.contains("--ui-collapsed")
            : UserDefaults.standard.bool(forKey: "Sparky.sidebarCollapsed"))
        let initial: Page = CommandLine.arguments.contains("--ui-contacts") ? .contacts : CommandLine.arguments.contains("--ui-history") ? .history : CommandLine.arguments.contains("--ui-settings") ? .settings : .plan
        self._page = ViewState(initialValue: initial)
    }
    private var filtered: [Contact] {
        model.saved.contacts.filter {
            (!selectedOnly || model.saved.selected.contains($0.id)) && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search))
        }
    }
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: sidebarCollapsed ? 80 : 225).clipped()
            Divider()
            VStack(spacing: 0) {
                pageHeader
                if model.busy { taskStatus }
                if page == .contacts { contacts }
                else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            switch page ?? .plan {
                            case .plan: plan
                            case .history: history
                            case .settings: settings
                            case .contacts: EmptyView()
                            }
                        }.frame(maxWidth: 760).frame(maxWidth: .infinity).padding(24)
                    }.safeAreaInset(edge: .bottom, spacing: 0) { if page == .plan { planActions } }
                }
            }.background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: SparkyMainWindow.minimumContentSize.width, minHeight: SparkyMainWindow.minimumContentSize.height).tint(.orange).environment(\.locale, Locale(identifier: "zh_CN"))
        .onAppear { model.confirmSend = { page = .plan; review = true } }
        .sheet(isPresented: $review) { reviewSheet }
        .alert("操作未完成", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button("好", role: .cancel) { model.notice = nil }
        } message: { Text(model.notice ?? "") }
        .confirmationDialog(loggingOut ? "退出抖音登录？" : "清空所有发送记录？", isPresented: Binding(get: { loggingOut || clearing }, set: { if !$0 { loggingOut = false; clearing = false } }), titleVisibility: .visible) {
            if loggingOut { Button("退出登录", role: .destructive) { Task { await model.logout() } }.disabled(model.busy) }
            else { Button("清空记录", role: .destructive) { model.clearHistory() } }
            Button("取消", role: .cancel) { }
        } message: {
            Text(loggingOut ? "将暂停定时计划并清空当前联系人，保留各账号的好友选择、消息模板与发送记录。仅退出本应用，不影响手机或 Safari。" : "这不会重置今天的定时任务，也不会重新发送。")
        }
    }
    private func toggleSidebar() {
        let keyboard = NSApp.currentEvent?.type == .keyDown || NSApp.currentEvent?.type == .keyUp
        if reduceMotion || keyboard { sidebarCollapsed.toggle() }
        else { withAnimation(.easeInOut(duration: 0.18)) { sidebarCollapsed.toggle() } }
        if !model.testing { UserDefaults.standard.set(sidebarCollapsed, forKey: "Sparky.sidebarCollapsed") }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 8) {
                if !sidebarCollapsed {
                    SparkyMark(size: 32)
                    Text("Sparky").font(.title3.weight(.semibold)).lineLimit(1)
                    Spacer(minLength: 0)
                }
                Button { toggleSidebar() } label: {
                    Image(systemName: "sidebar.left").font(.system(size: 16)).frame(width: 28, height: 32)
                }.buttonStyle(SparkyRowStyle()).foregroundStyle(.secondary)
                    .help(sidebarCollapsed ? "展开侧栏" : "收起侧栏")
                    .accessibilityLabel(sidebarCollapsed ? "展开侧栏" : "收起侧栏")
                    .accessibilityValue(sidebarCollapsed ? "已折叠" : "已展开")
                    .accessibilityIdentifier("sidebar.toggle")
                    .keyboardShortcut("s", modifiers: [.command, .control])
            }.frame(maxWidth: .infinity).frame(height: 40).padding(.horizontal, 12).padding(.top, 42)
            VStack(spacing: 4) {
                ForEach(Page.allCases) { item in
                    Button { page = item } label: {
                        HStack(spacing: 10) {
                            Image(systemName: item.icon).font(.system(size: 15)).frame(width: 20)
                                .foregroundStyle(page == item ? Color.orange : Color.secondary)
                            if !sidebarCollapsed {
                                Text(item.rawValue).fontWeight(page == item ? .medium : .regular).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                        }.frame(maxWidth: .infinity, minHeight: 20).padding(.horizontal, 12).padding(.vertical, 9)
                    }.buttonStyle(SparkyRowStyle(selected: page == item))
                        .help(item.rawValue).accessibilityLabel(item.rawValue).accessibilityIdentifier("sidebar.\(item.rawValue)")
                        .accessibilityAddTraits(page == item ? .isSelected : [])
                }
            }.padding(.horizontal, 10)
            Spacer(minLength: 0)
            if sidebarCollapsed { compactAccountFooter }
            else { accountFooter }
        }.frame(maxHeight: .infinity)
        .background { if reduceTransparency { Color(nsColor: .windowBackgroundColor) } else { SidebarBackdrop() } }
    }
    private var compactAccountFooter: some View {
        VStack(spacing: 10) {
            Button {
                if model.saved.account == nil && model.saved.logoutPending != true { model.connect() }
                else { page = .settings }
            } label: {
                Image(systemName: "person.crop.circle").font(.system(size: 23)).frame(width: 40, height: 36)
                    .overlay(alignment: .bottomTrailing) {
                        Circle().fill(model.busy ? Color.orange : model.saved.account == nil ? Color.secondary : .green).frame(width: 6, height: 6).padding(4)
                    }
            }.buttonStyle(SparkyRowStyle()).foregroundStyle(.secondary)
                .disabled(model.saved.account == nil && model.busy)
                .help(model.saved.account?.nickname ?? "登录抖音")
                .accessibilityLabel(model.saved.account == nil ? "登录抖音" : "账号设置")
                .accessibilityIdentifier(model.saved.account == nil ? "account.login" : "account.settings")
            if model.loginInProgress {
                Button { model.cancelLogin() } label: { Image(systemName: "xmark.circle").frame(width: 40, height: 30) }
                    .buttonStyle(SparkyRowStyle()).help("取消登录").accessibilityLabel("取消登录")
            } else if model.saved.account != nil || model.saved.logoutPending == true {
                Button { loggingOut = true } label: { Image(systemName: "rectangle.portrait.and.arrow.right").frame(width: 40, height: 30) }
                    .buttonStyle(SparkyRowStyle()).foregroundStyle(.secondary).disabled(model.busy)
                    .help("退出登录").accessibilityLabel("退出登录").accessibilityIdentifier("account.logout.sidebar")
            }
        }.frame(maxWidth: .infinity).padding(.vertical, 14)
    }
    private var accountFooter: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Circle().fill(model.busy ? Color.orange : model.saved.account == nil ? Color.secondary : .green).frame(width: 6, height: 6)
                Text(model.busy ? (model.loginInProgress ? "等待登录" : "任务进行中") : model.saved.account == nil ? "尚未登录" : "后台待命").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle.fill").font(.system(size: 27)).foregroundStyle(.secondary).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.saved.account?.nickname ?? "连接抖音账号").font(.subheadline.weight(.medium)).lineLimit(1).truncationMode(.middle)
                    Text(model.saved.account == nil ? "登录后同步联系人" : "好友选择已保存在本机").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if model.loginInProgress {
                    Button("取消") { model.cancelLogin() }.buttonStyle(.borderless).help("取消登录")
                } else if model.saved.account != nil || model.saved.logoutPending == true {
                    Button { loggingOut = true } label: { Image(systemName: "rectangle.portrait.and.arrow.right").frame(width: 26, height: 28) }
                        .buttonStyle(.borderless).foregroundStyle(.secondary).disabled(model.busy).help("退出登录")
                        .accessibilityLabel("退出登录").accessibilityIdentifier("account.logout.sidebar")
                } else { Button("登录") { model.connect() }.buttonStyle(.borderless).disabled(model.busy).accessibilityIdentifier("account.login") }
            }
        }.padding(14).overlay(alignment: .top) { Divider().padding(.horizontal, 14) }
    }
    private var pageHeader: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text((page ?? .plan).rawValue).font(.title2.weight(.semibold)).accessibilityIdentifier("page.title")
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if page == .contacts {
                Button { model.refresh() } label: { Label("刷新联系人", systemImage: "arrow.clockwise") }.disabled(model.busy).accessibilityIdentifier("contacts.refresh")
            } else if page == .history {
                Button("清空记录…") { clearing = true }.disabled(model.busy || model.saved.history.isEmpty)
            }
        }.padding(.horizontal, 24).padding(.top, 26).padding(.bottom, 16).frame(minHeight: 84)
    }
    private var subtitle: String {
        switch page ?? .plan {
        case .plan: return "安排好一句问候，其他的交给 Sparky。"
        case .contacts: return "选择每天想联系的人。"
        case .history: return "查看每一次发送的实际结果。"
        case .settings: return "管理账号与应用偏好。"
        }
    }
    private var taskStatus: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                if !model.sending { ProgressView().controlSize(.small) }
                Text(model.activity).font(.callout).lineLimit(2).accessibilityIdentifier("task.activity")
                Spacer()
                if model.loginInProgress { Button("取消登录") { model.cancelLogin() } }
                else if model.sending {
                    Button(model.cancelRequested ? "正在停止…" : "停止后续发送") { model.cancelRequested = true }
                        .disabled(model.cancelRequested).accessibilityIdentifier("task.stop")
                }
            }
            if model.sending {
                ProgressView(value: Double(model.progress), total: Double(max(1, model.total))).accessibilityLabel("发送进度")
            }
        }.padding(.horizontal, 24).padding(.vertical, 12).background(Color.orange.opacity(0.06))
    }
    private var plan: some View {
        Group {
            if model.saved.account == nil {
                SparkySurface {
                    HStack(spacing: 12) {
                        SparkyIcon(symbol: "person.crop.circle.badge.plus")
                        VStack(alignment: .leading, spacing: 3) { Text("从连接抖音开始").font(.headline); Text("登录后会自动读取联系人，并恢复你的选择。").font(.caption).foregroundStyle(.secondary) }
                        Spacer(); Button("登录抖音") { model.connect() }.disabled(model.busy)
                    }.padding(16)
                }
            }
            planOverview
            SparkySection("发送内容") {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("写一句想发的话…", text: Binding(get: { model.saved.message }, set: { value in model.edit { $0.message = value } }))
                        .textFieldStyle(.plain).font(.system(size: 15)).padding(14).frame(minHeight: 56, alignment: .leading)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                        .disabled(model.busy).accessibilityLabel("发送内容").accessibilityIdentifier("plan.message")
                    HStack {
                        Text(model.messageValid ? "单行消息" : "请填写单行消息，长度不超过 500").foregroundStyle(model.messageValid ? Color.secondary : .red)
                        Spacer(); Text("\(model.saved.message.utf16.count) / 500").foregroundStyle(.secondary).monospacedDigit()
                    }.font(.caption)
                }.padding(16)
            }
            schedule
            recipients
        }
    }
    private var planOverview: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "clock").font(.system(size: 27, weight: .light)).foregroundStyle(.orange).frame(width: 52, height: 52).background(Color.orange.opacity(0.08), in: Circle()).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(model.saved.plan.enabled ? "每天 \(displayDate(model.timeDate))" : "让问候成为日常").font(.title2.weight(.semibold)).monospacedDigit()
                Text(model.nextRun.map { "下次发送 · " + displayDate($0, withDay: true) } ?? "选好好友和时间后，开启每日定时。").font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(model.saved.plan.enabled ? "计划已开启" : "计划已暂停").font(.caption.weight(.medium)).foregroundStyle(model.saved.plan.enabled ? Color.green : .secondary)
                .padding(.horizontal, 10).padding(.vertical, 6).background(Color.primary.opacity(0.045), in: Capsule())
        }.padding(.vertical, 4)
    }
    private var schedule: some View {
        SparkySection("每日定时", footer: "Mac 休眠时不发送，唤醒后只补当日任务；开启时已错过的时间从明天开始。") {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    SparkyIcon(symbol: "calendar", color: .blue)
                    VStack(alignment: .leading, spacing: 3) { Text("自动发送"); Text("保持 Sparky 在菜单栏运行").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Toggle("自动发送", isOn: Binding(get: { model.saved.plan.enabled }, set: { model.setSchedule($0) })).labelsHidden().toggleStyle(.switch).disabled(model.busy).accessibilityIdentifier("plan.schedule")
                }.padding(16)
                Divider().padding(.leading, 58)
                HStack {
                    Text("发送时间")
                    Spacer()
                    DatePicker("发送时间", selection: Binding(get: { model.timeDate }, set: { model.setTime($0) }), displayedComponents: .hourAndMinute).labelsHidden().datePickerStyle(.field).fixedSize().disabled(model.busy).accessibilityIdentifier("plan.time")
                    Text("本地时间").font(.caption).foregroundStyle(.secondary).help(TimeZone.current.localizedName(for: .standard, locale: Locale(identifier: "zh_CN")) ?? TimeZone.current.identifier)
                }.padding(.horizontal, 16).padding(.vertical, 12)
            }
        }
    }
    private var recipients: some View {
        SparkySection("接收人") {
            HStack(spacing: 12) {
                if let first = model.selectedContacts.first { ContactAvatar(contact: first) }
                else { SparkyIcon(symbol: "person.2", color: .purple) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.selectedContacts.isEmpty ? "还没有选择好友" : "已选择 \(model.selectedContacts.count) 个会话").font(.body.weight(.medium))
                    Text(model.selectedContacts.isEmpty ? "从已有私聊或群聊中选择" : model.selectedContacts.map(\.title).joined(separator: "、")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 12)
                Button("选择好友…") { page = .contacts }.accessibilityIdentifier("plan.recipients")
            }.padding(16)
        }
    }
    private var planActions: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("今日已确认 \(model.todayConfirmed) 个会话").font(.callout).monospacedDigit()
                Text(model.todayAttention > 0 ? "\(model.todayAttention) 条记录需要核实" : "发送前核对名单，发送后记录结果").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { review = true } label: { Label("立即执行…", systemImage: "paperplane.fill").padding(.horizontal, 4) }
                .buttonStyle(.borderedProminent).controlSize(.large).disabled(!model.canRun || model.busy).accessibilityIdentifier("plan.run")
        }.padding(.horizontal, 24).padding(.vertical, 14).background(.bar)
    }
    private var contacts: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                    TextField("搜索好友或群聊", text: $search).textFieldStyle(.plain).accessibilityLabel("搜索联系人").accessibilityIdentifier("contacts.search")
                    if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary).help("清除搜索").accessibilityLabel("清除搜索").accessibilityIdentifier("contacts.clear") }
                }.padding(8).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7)).overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.primary.opacity(0.1)))
                Picker("联系人范围", selection: $selectedOnly) { Text("全部").tag(false); Text("已选").tag(true) }.pickerStyle(.segmented).labelsHidden().frame(width: 142).accessibilityIdentifier("contacts.scope")
            }.padding(.horizontal, 24).padding(.vertical, 16)
            Group {
            if model.saved.contacts.isEmpty {
                SparkyEmptyState("先连接你的抖音账号", symbol: "person.crop.circle.badge.plus", description: "登录后自动读取已有聊天会话，选好好友后即可设置每日发送。") {
                    Button("登录抖音") { model.connect() }.buttonStyle(.borderedProminent).disabled(model.busy)
                    if model.saved.account != nil { Button("重新读取联系人") { model.refresh() }.disabled(model.busy) }
                }
            } else if filtered.isEmpty {
                SparkyEmptyState(selectedOnly && search.isEmpty ? "还没有选择好友" : "没有找到匹配的会话", symbol: "magnifyingglass", description: selectedOnly ? "切换到“全部”来选择好友，或试试其他关键词。" : "试试其他名字，或刷新联系人列表。") {
                    Button(selectedOnly ? "显示全部联系人" : "清除搜索") { search = ""; selectedOnly = false }
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filtered) { contact in contactRow(contact) }
                    }.padding(.horizontal, 16).padding(.bottom, 16)
                }
            }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: 12) {
                Text("已选 \(model.selectedContacts.count) / \(model.saved.contacts.count)").font(.callout).foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                Button("全选当前列表") { model.select(filtered, enabled: true) }.disabled(model.busy || filtered.isEmpty).accessibilityIdentifier("contacts.selectAll")
                Button("取消选择") { model.select(filtered, enabled: false) }.disabled(model.busy || !filtered.contains { model.saved.selected.contains($0.id) })
            }.padding(.horizontal, 24).padding(.vertical, 12).background(.bar)
        }
    }
    private func contactRow(_ contact: Contact) -> some View {
        let selected = model.saved.selected.contains(contact.id)
        return Button { model.toggleContact(contact.id) } label: {
            HStack(spacing: 12) {
                ContactAvatar(contact: contact)
                VStack(alignment: .leading, spacing: 4) { Text(contact.title).font(.body.weight(.medium)).lineLimit(1).truncationMode(.middle); Text(contact.group ? "群聊" : "私聊").font(.caption).foregroundStyle(.secondary) }
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle").font(.system(size: 19)).foregroundStyle(selected ? Color.orange : Color(nsColor: .tertiaryLabelColor)).accessibilityHidden(true)
            }.padding(.horizontal, 12).padding(.vertical, 10).frame(maxWidth: .infinity)
        }.buttonStyle(SparkyRowStyle(selected: selected)).disabled(model.busy)
            .accessibilityLabel(contact.title + (contact.group ? "，群聊" : "，私聊")).accessibilityValue(selected ? "已选择" : "未选择")
            .accessibilityAddTraits(selected ? .isSelected : []).accessibilityIdentifier("contact.\(contact.id)")
    }
    private var history: some View {
        Group {
            if model.saved.history.isEmpty {
                SparkyEmptyState("还没有发送记录", symbol: "tray", description: "完成一次发送后，就能在这里查看每位好友的结果。") { Button("前往发送计划") { page = .plan } }
            } else {
                HStack(spacing: 20) {
                    Label("今日确认 \(model.todayConfirmed)", systemImage: "checkmark.circle").foregroundStyle(.green)
                    if model.todayAttention > 0 { Label("需要核实 \(model.todayAttention)", systemImage: "exclamationmark.circle").foregroundStyle(.orange) }
                    Spacer(); Text("最近 2,000 条").foregroundStyle(.secondary)
                }.font(.callout)
                ForEach(historyGroups, id: \.day) { group in
                    SparkySection(dayLabel(group.day)) {
                        VStack(spacing: 0) {
                            ForEach(group.records) { record in
                                HistoryRow(record: record).padding(.horizontal, 16).padding(.vertical, 12)
                                if record.id != group.records.last?.id { Divider().padding(.leading, 16) }
                            }
                        }
                    }
                }
                Text("服务器确认不代表已读或火花更新。页面确认和待确认结果，请用手机核实后再决定是否重发。").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var historyGroups: [(day: Date, records: [SendRecord])] {
        let grouped = Dictionary(grouping: model.saved.history.reversed()) { Calendar.current.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { (day: $0, records: grouped[$0] ?? []) }
    }
    private func dayLabel(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "今天" }
        if Calendar.current.isDateInYesterday(day) { return "昨天" }
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = "M月d日"; return f.string(from: day)
    }
    private var settings: some View {
        Group {
            accountSettings
            SparkySection("通用") {
                HStack(spacing: 12) {
                    SparkyIcon(symbol: "power", color: .green)
                    VStack(alignment: .leading, spacing: 3) { Text("登录 Mac 时启动"); Text("在菜单栏中等待每日任务").font(.caption).foregroundStyle(.secondary) }
                    Spacer(); Toggle("登录 Mac 时启动 Sparky", isOn: Binding(get: { model.loginEnabled }, set: { model.setLoginItem($0) })).labelsHidden().toggleStyle(.switch).accessibilityLabel("登录 Mac 时启动 Sparky")
                }.padding(16)
            }
            SparkySection("诊断", footer: "任务结束后自动释放网页，登录状态保留。") {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 12) {
                        SparkyIcon(symbol: "waveform.path", color: .purple)
                        VStack(alignment: .leading, spacing: 3) { Text("连接引擎"); Text(model.engineActive ? "正在运行" : "已休眠 · 按需启动").font(.caption).foregroundStyle(.secondary) }
                        Spacer(); Button("释放引擎") { model.releaseEngine() }.disabled(model.busy || !model.engineActive)
                    }.padding(16)
                    Divider().padding(.leading, 16)
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(model.logs.isEmpty ? "暂无日志" : model.logs.suffix(20).joined(separator: "\n")).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            Button("复制日志") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(model.logs.joined(separator: "\n"), forType: .string) }
                        }.padding(.top, 12)
                    } label: { Text("运行日志") }.padding(16)
                }
            }
            HStack(spacing: 10) {
                SparkyMark(size: 34)
                VStack(alignment: .leading, spacing: 3) { Text("Sparky 0.3.2").font(.caption.weight(.medium)); Text("设置与记录保存在本机").font(.caption).foregroundStyle(.secondary) }
                Spacer()
            }.padding(.horizontal, 4)
        }
    }
    private var accountSettings: some View {
        SparkySection("抖音账号", footer: "登录后自动读取联系人并恢复选择。退出或切换账号后，需手动开启定时计划。") {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.fill").font(.system(size: 38)).foregroundStyle(.secondary).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.saved.account?.nickname ?? "尚未登录").font(.body.weight(.semibold)).lineLimit(2)
                        Text(model.saved.account.map { $0.douyinID.isEmpty ? "已连接抖音" : "抖音号 · " + $0.douyinID } ?? "连接后同步已有聊天会话").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if model.loginInProgress { Button("取消登录") { model.cancelLogin() } }
                    else { Button(model.saved.account == nil ? "登录抖音" : "打开登录窗口") { model.connect() }.disabled(model.busy) }
                }.padding(16)
                Divider().padding(.leading, 16)
                HStack {
                    Button("刷新账号与联系人") { model.refresh() }.disabled(model.busy)
                    Spacer()
                    Button("退出登录", role: .destructive) { loggingOut = true }.disabled(model.busy).accessibilityIdentifier("account.logout.settings")
                }.padding(.horizontal, 16).padding(.vertical, 12)
            }
        }
    }
    private var reviewSheet: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                SparkyIcon(symbol: "paperplane.fill")
                VStack(alignment: .leading, spacing: 4) { Text("确认这次问候").font(.title2.weight(.semibold)); Text("发送给 \(model.selectedContacts.count) 个会话").foregroundStyle(.secondary) }
            }
            SparkySurface { Text(model.saved.message).font(.body).textSelection(.enabled).padding(16) }
            ScrollView { VStack(alignment: .leading, spacing: 10) { ForEach(model.selectedContacts) { contact in HStack(spacing: 10) { ContactAvatar(contact: contact); Text(contact.title); Spacer() } } }.padding(.trailing, 8) }.frame(maxHeight: 180)
            Text("逐个发送，每个会话只触发一次。本次执行计入今日计划，今天不会再自动发送。").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer(); Button("取消") { review = false }.keyboardShortcut(.cancelAction)
                Button("确认发送") { review = false; Task { await model.runBatch(scheduled: false) } }.buttonStyle(.borderedProminent).disabled(!model.canRun || model.busy).accessibilityIdentifier("review.confirm")
            }
        }.padding(24).frame(width: 450)
    }
}

private struct HistoryRow: View {
    let record: SendRecord
    private var color: Color {
        switch record.state { case .confirmed: return .green; case .pageOnly: return .blue; case .failed, .rejected: return .red; case .cancelled: return .secondary; default: return .orange }
    }
    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                Text(record.detail).textSelection(.enabled)
                if !record.messageID.isEmpty { Text("消息 ID · \(record.messageID)").font(.caption.monospaced()).textSelection(.enabled) }
            }.font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) { Text(record.name).font(.body.weight(.medium)).lineLimit(1); Text(displayDate(record.date) + (record.scheduled ? " · 定时发送" : " · 手动执行")).font(.caption).foregroundStyle(.secondary) }
                Spacer(minLength: 8)
                Label(record.state.label, systemImage: record.state == .confirmed ? "checkmark.circle.fill" : "info.circle").font(.caption.weight(.medium)).foregroundStyle(color)
            }
        }
    }
}
