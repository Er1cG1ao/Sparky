import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var model: SparkyModel!
    var window: NSWindow!
    var status: NSStatusItem!
    let test = CommandLine.arguments.contains("--self-test")
    let preview = CommandLine.arguments.contains("--ui-smoke")
    let windowTest = CommandLine.arguments.contains("--window-self-test")
    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let engine = try BrowserEngine(selfTest:test || preview || windowTest)
            let directory = (test || preview || windowTest) ? FileManager.default.temporaryDirectory.appendingPathComponent("spark-test-\(UUID().uuidString)") : FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Spark")
            model = SparkyModel(store:LocalStore(directory:directory),engine:engine,testing:test || preview || windowTest)
            if test { Task { do { if CommandLine.arguments.contains("--logout-only") { try await LogoutTests.run() } else if CommandLine.arguments.contains("--scan-only") { try await ContactScanTests.run() } else if CommandLine.arguments.contains("--login-only") { try await LoginTests.run() } else { try await SelfTests.run(model) }; print("PASS: all Sparky offline tests"); fflush(stdout); exit(0) } catch { fputs("FAIL: \(error)\n",stderr); exit(1) } }; return }
            if preview || windowTest { model.seedPreview() }
            window = SparkyMainWindow(contentRect:NSRect(x:0,y:0,width:1030,height:800),styleMask:[.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView],backing:.buffered,defer:false)
            window.title = "Sparky"; window.titleVisibility = .hidden; window.toolbar = nil; window.titlebarAppearsTransparent = true; window.titlebarSeparatorStyle = .none; window.isOpaque = false; window.backgroundColor = .clear; window.isReleasedWhenClosed = false; window.delegate = self
            (window as? SparkyMainWindow)?.configureWindowRules()
            let viewModel = model!
            let hostingView = NSHostingView(rootView: GeometryReader { geometry in
                SparkyView(model:viewModel).frame(width:geometry.size.width,height:geometry.size.height)
            }.ignoresSafeArea(.container, edges: .top))
            hostingView.sizingOptions = []
            window.contentView = hostingView
            (window as? SparkyMainWindow)?.installWindowControls()
            window.center()
            status = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
            status.button?.image = NSImage(systemSymbolName:"flame",accessibilityDescription:"Sparky")
            configureMainMenu()
            model.changed = { [weak self] in self?.updateMenu() }; updateMenu()
            if !CommandLine.arguments.contains("--background") { show() }
            if windowTest {
                Task {
                    do { try await WindowTests.run(self); print("PASS: native window tests"); fflush(stdout); exit(0) }
                    catch { fputs("FAIL: \(error.localizedDescription)\n",stderr); exit(1) }
                }
                return
            }
            if preview {
                window.appearance = NSAppearance(named: CommandLine.arguments.contains("--ui-dark") ? .darkAqua : .aqua)
                if CommandLine.arguments.contains("--ui-compact") { window.setContentSize(SparkyMainWindow.minimumContentSize) }
                if CommandLine.arguments.contains("--ui-tall") { window.performZoom(nil) }
                if CommandLine.arguments.contains("--ui-empty") { try? model.commit { $0.account=nil; $0.contacts=[]; $0.selected=[]; $0.history=[]; $0.plan.enabled=false } }
                if CommandLine.arguments.contains("--ui-stress") {
                    try? model.commit { state in
                        state.account?.nickname = String(repeating: "很长的昵称", count: 12)
                        state.contacts.append(Contact(id:"long-name",title:String(repeating:"这是一个很长的群聊名称",count:12),group:true))
                    }
                }
                if CommandLine.arguments.contains("--ui-loading") { model.busy=true; model.engine.busy=true; model.activity="正在读取联系人…" }
                DispatchQueue.main.asyncAfter(deadline:.now()+2) { [self] in
                    window.makeFirstResponder(nil)
                    let view = window.contentView!.superview ?? window.contentView!; view.layoutSubtreeIfNeeded()
                    if let bitmap = view.bitmapImageRepForCachingDisplay(in:view.bounds) { view.cacheDisplay(in:view.bounds,to:bitmap); try? bitmap.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:"/tmp/spark-native-ui.png")) }
                    print("UI smoke complete"); fflush(stdout); exit(0)
                }
            }
        } catch { let alert = NSAlert(); alert.messageText = "Sparky 启动失败"; alert.informativeText = error.localizedDescription; alert.runModal(); NSApp.terminate(nil) }
    }
    func updateMenu() {
        guard status != nil else { return }
        let menu = NSMenu()
        let summary = NSMenuItem(title:model.busy ? model.activity : (model.nextRun.map { "下次发送 · " + displayDate($0,withDay:true) } ?? "定时发送未开启"),action:nil,keyEquivalent:""); menu.addItem(summary); menu.addItem(.separator())
        item(menu,"打开 Sparky",#selector(show),"o")
        let send = item(menu,"立即执行…",#selector(review),""); send.isEnabled = model.canRun && !model.busy
        let pause = item(menu,model.saved.plan.enabled ? "暂停定时发送" : "开启定时发送",#selector(togglePlan),""); pause.isEnabled = !model.busy && (model.saved.plan.enabled || model.canRun)
        menu.addItem(.separator()); item(menu,"退出 Sparky",#selector(quit),"q")
        menu.autoenablesItems = false; status.menu = menu; status.button?.toolTip = "Sparky · \(model.activity)"
    }
    @discardableResult func item(_ menu:NSMenu,_ text:String,_ selector:Selector,_ key:String) -> NSMenuItem { let i=NSMenuItem(title:text,action:selector,keyEquivalent:key); i.target=self; menu.addItem(i); return i }
    func configureMainMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu(title:"Sparky")
        item(appMenu,"隐藏 Sparky",#selector(NSApplication.hide(_:)),"h").target = NSApp
        let hideOthers = item(appMenu,"隐藏其他",#selector(NSApplication.hideOtherApplications(_:)),"h")
        hideOthers.target = NSApp; hideOthers.keyEquivalentModifierMask = [.command,.option]
        item(appMenu,"显示全部",#selector(NSApplication.unhideAllApplications(_:)),"").target = NSApp
        appMenu.addItem(.separator()); item(appMenu,"退出 Sparky",#selector(quit),"q")
        appItem.submenu = appMenu; menu.addItem(appItem)

        let fileItem = NSMenuItem(); let fileMenu = NSMenu(title:"文件")
        let close = NSMenuItem(title:"关闭窗口",action:#selector(NSWindow.performClose(_:)),keyEquivalent:"w")
        close.keyEquivalentModifierMask = [.command]; fileMenu.addItem(close)
        fileItem.submenu = fileMenu; menu.addItem(fileItem)

        let editItem = NSMenuItem(); let editMenu = NSMenu(title:"编辑")
        for (title, action, key) in [("撤销","undo:","z"),("重做","redo:","Z"),("剪切","cut:","x"),("拷贝","copy:","c"),("粘贴","paste:","v"),("全选","selectAll:","a")] {
            editMenu.addItem(NSMenuItem(title:title,action:NSSelectorFromString(action),keyEquivalent:key))
        }
        editItem.submenu = editMenu; menu.addItem(editItem)
        let windowItem = NSMenuItem(); let windowMenu = NSMenu(title:"窗口")
        windowMenu.addItem(NSMenuItem(title:"最小化",action:#selector(NSWindow.performMiniaturize(_:)),keyEquivalent:"m"))
        windowMenu.addItem(NSMenuItem(title:"拉高／恢复窗口",action:#selector(NSWindow.performZoom(_:)),keyEquivalent:""))
        windowItem.submenu = windowMenu; menu.addItem(windowItem)
        NSApp.mainMenu = menu; NSApp.windowsMenu = windowMenu
    }
    @objc func show() {
        NSApp.setActivationPolicy(.regular)
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps:true)
    }
    func windowDidResize(_ notification:Notification) {
        (notification.object as? SparkyMainWindow)?.positionWindowControls()
    }
    func windowDidUpdate(_ notification:Notification) {
        (notification.object as? SparkyMainWindow)?.positionWindowControls()
    }
    func windowWillResize(_ sender:NSWindow,to frameSize:NSSize) -> NSSize {
        (sender as? SparkyMainWindow)?.constrainedFrameSize(frameSize) ?? frameSize
    }
    func windowWillClose(_ notification:Notification) {
        guard let closing = notification.object as? NSWindow, closing === window else { return }
        NSApp.setActivationPolicy(.accessory)
    }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool) -> Bool {
        show(); return false
    }
    @objc func review() { show(); model.confirmSend?() }
    @objc func togglePlan() { model.setSchedule(!model.saved.plan.enabled) }
    @objc func quit() {
        if model.loginInProgress { model.cancelLogin(); NSApp.terminate(nil); return }
        if model.busy { model.cancelRequested=true; model.notice="已请求停止后续发送。请等待当前会话完成，再退出 Sparky。"; show(); return }
        NSApp.terminate(nil)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication) -> Bool { false }
}
MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
