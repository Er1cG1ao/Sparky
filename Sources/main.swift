import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var model: SparkyModel!
    var window: NSWindow!
    var status: NSStatusItem!
    let test = CommandLine.arguments.contains("--self-test")
    let preview = CommandLine.arguments.contains("--ui-smoke")
    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let engine = try BrowserEngine(selfTest:test || preview)
            let directory = (test || preview) ? FileManager.default.temporaryDirectory.appendingPathComponent("spark-test-\(UUID().uuidString)") : FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Spark")
            model = SparkyModel(store:LocalStore(directory:directory),engine:engine,testing:test || preview)
            if test { Task { do { try await SelfTests.run(model); print("PASS: all Sparky offline tests"); fflush(stdout); exit(0) } catch { fputs("FAIL: \(error)\n",stderr); exit(1) } }; return }
            if preview { model.seedPreview() }
            window = NSWindow(contentRect:NSRect(x:0,y:0,width:1030,height:800),styleMask:[.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView],backing:.buffered,defer:false)
            window.title = "Sparky"; window.titleVisibility = .hidden; window.toolbar = NSToolbar(identifier:"SparkToolbar"); window.toolbarStyle = .unified; window.isReleasedWhenClosed = false; window.delegate = self
            window.contentView = NSHostingView(rootView:SparkyView(model:model)); window.minSize = NSSize(width:900,height:690); window.center()
            status = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
            status.button?.image = NSImage(systemSymbolName:"flame",accessibilityDescription:"Sparky")
            model.changed = { [weak self] in self?.updateMenu() }; updateMenu()
            if !CommandLine.arguments.contains("--background") { show() }
            if preview {
                window.appearance = NSAppearance(named:.aqua)
                DispatchQueue.main.asyncAfter(deadline:.now()+2) { [self] in
                    window.makeFirstResponder(nil)
                    let view = window.contentView!; view.layoutSubtreeIfNeeded()
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
    @objc func show() { NSApp.activate(ignoringOtherApps:true); window.makeKeyAndOrderFront(nil) }
    @objc func review() { show(); model.confirmSend?() }
    @objc func togglePlan() { model.setSchedule(!model.saved.plan.enabled) }
    @objc func quit() {
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
