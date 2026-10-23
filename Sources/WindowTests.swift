import AppKit

@MainActor
enum WindowTests {
    // SwiftUI virtual accessibility nodes use the informal NSObject protocol.
    static func attribute(_ root:Any,_ key:String) -> Any? {
        guard let node=root as? NSObject, node.responds(to:NSSelectorFromString(key)) else { return nil }
        return node.value(forKey:key)
    }
    static func find(_ root:Any,_ id:String) -> Any? {
        if attribute(root,"accessibilityIdentifier") as? String == id { return root }
        for child in attribute(root,"accessibilityChildren") as? [Any] ?? [] {
            if let found=find(child,id) { return found }
        }
        return nil
    }
    static func pause() async throws { try await Task.sleep(nanoseconds:350_000_000) }
    static func run(_ delegate:AppDelegate) async throws {
        DispatchQueue.main.asyncAfter(deadline:.now()+25) { fputs("FAIL: native window test timeout\n",stderr); exit(1) }
        try await pause()
        let window=delegate.window!, model=delegate.model!
        try SelfTests.check(window.isVisible && NSApp.activationPolicy() == .regular,"visible main window uses regular Dock application policy")
        // The right edge is deliberately outside the icon and text, inside the
        // same rounded row background users see as the selection highlight.
        for name in ["联系人","发送记录","设置","发送计划"] {
            guard let button=find(window,"sidebar.\(name)") else { throw PrototypeError.message("Sidebar button missing: \(name)") }
            guard let frame=(attribute(button,"accessibilityFrame") as? NSValue)?.rectValue else { throw PrototypeError.message("Sidebar frame missing") }
            try SelfTests.check(frame.width > 140,"sidebar \(name) exposes a full-width clickable row")
            let point=window.convertPoint(fromScreen:NSPoint(x:frame.maxX-12,y:frame.midY))
            for type in [NSEvent.EventType.leftMouseDown,.leftMouseUp] {
                let event=NSEvent.mouseEvent(with:type,location:point,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:0)!
                NSApp.postEvent(event,atStart:false)
            }
            try await pause()
            let title=find(window,"page.title").flatMap { attribute($0,"accessibilityValue") as? String ?? attribute($0,"accessibilityLabel") as? String }
            try SelfTests.check(title == name,"clicking empty row space opens \(name), title=\(title ?? "nil")")
        }
        window.makeFirstResponder(nil)
        let event=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[.command],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,context:nil,characters:"w",charactersIgnoringModifiers:"w",isARepeat:false,keyCode:13)!
        let handled=NSApp.mainMenu!.performKeyEquivalent(with:event)
        try await pause()
        try SelfTests.check(handled && !window.isVisible,"Command-W closes the main window through the native menu")
        try SelfTests.check(NSApp.activationPolicy() == .accessory,"closing the main window hides Dock presence")
        try SelfTests.check(model.saved.plan.enabled && delegate.status != nil && model.engine.webView == nil,"closing leaves the plan and menu bar app intact without starting WebKit")
        delegate.show(); try await pause()
        try SelfTests.check(window.isVisible && NSApp.activationPolicy() == .regular,"menu-bar reopen restores Dock presence")
        window.miniaturize(nil); try await pause()
        try SelfTests.check(NSApp.activationPolicy() == .regular,"minimizing keeps Dock presence")
        _ = delegate.applicationShouldHandleReopen(NSApp,hasVisibleWindows:false)
        try await pause()
        try SelfTests.check(window.isVisible && !window.isMiniaturized,"Dock reopen restores a minimized main window")
        window.performClose(nil); try await pause()
        try SelfTests.check(NSApp.activationPolicy() == .accessory,"red close button returns to menu-bar mode")
        try? FileManager.default.removeItem(at:model.store.directory)
    }
}
