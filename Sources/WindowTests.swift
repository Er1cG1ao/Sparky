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
    static func click(_ window:NSWindow, id:String, fraction:CGFloat = 0.5) async throws {
        guard let element=find(window,id), let frame=(attribute(element,"accessibilityFrame") as? NSValue)?.rectValue else { throw PrototypeError.message("Missing clickable UI: \(id)") }
        let point=window.convertPoint(fromScreen:NSPoint(x:frame.minX+frame.width*fraction,y:frame.midY))
        for type in [NSEvent.EventType.leftMouseDown,.leftMouseUp] {
            NSApp.postEvent(NSEvent.mouseEvent(with:type,location:point,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:0)!,atStart:false)
        }
        try await pause()
    }
    static func run(_ delegate:AppDelegate) async throws {
        DispatchQueue.main.asyncAfter(deadline:.now()+45) { fputs("FAIL: native window test timeout\n",stderr); exit(1) }
        try await pause()
        let window=delegate.window!, model=delegate.model!
        try SelfTests.check(window.isVisible && NSApp.activationPolicy() == .regular,"visible main window uses regular Dock application policy")
        try SelfTests.check(find(window,"account.logout.sidebar") != nil,"sidebar exposes logout beside the account name")
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
            if name == "联系人" {
                let wasSelected=model.saved.selected.contains("a")
                try await click(window,id:"contact.a",fraction:0.7)
                try SelfTests.check(model.saved.selected.contains("a") != wasSelected,"contact selection responds to empty space across the full row")
                try SelfTests.check(try model.store.load().selected == model.saved.selected,"row selection is persisted through the model")
                try await click(window,id:"contacts.scope",fraction:0.75)
                try SelfTests.check(find(window,"contact.a") == nil && find(window,"contact.b") != nil,"selected-only filter hides unselected contacts")
                try await click(window,id:"contacts.scope",fraction:0.25)
                try await click(window,id:"contacts.search")
                guard let editor=window.firstResponder as? NSTextView else { throw PrototypeError.message("Search editor did not receive keyboard focus") }
                editor.insertText("不会匹配的搜索",replacementRange:NSRange(location:NSNotFound,length:0))
                try await pause()
                try SelfTests.check(find(window,"contact.b") == nil && find(window,"contacts.clear") != nil,"keyboard search produces an actionable empty state")
                try await click(window,id:"contacts.clear")
                try SelfTests.check(find(window,"contact.b") != nil,"clearing search restores contact rows")
                try await click(window,id:"contact.a",fraction:0.7)
                try SelfTests.check(model.saved.selected.contains("a") == wasSelected,"repeated row clicks toggle predictably without changing other recipients")
            }
            if name == "设置" { try SelfTests.check(find(window,"account.logout.settings") != nil,"settings exposes the same logout action") }
        }
        let previousHistory=model.saved.history.count
        try await click(window,id:"plan.run")
        guard let sheet=window.attachedSheet else { throw PrototypeError.message("Send review sheet did not appear") }
        try SelfTests.check(find(sheet,"review.confirm") != nil && model.engine.webView == nil,"run button opens a recipient review before starting the engine")
        let escape=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:sheet.windowNumber,context:nil,characters:"\u{1b}",charactersIgnoringModifiers:"\u{1b}",isARepeat:false,keyCode:53)!
        NSApp.sendEvent(escape); try await pause()
        try SelfTests.check(window.attachedSheet == nil && model.saved.history.count == previousHistory,"Escape cancels review without sending or recording a batch")
        model.busy=true; model.engine.busy=true; model.activity="正在读取联系人…"
        try await pause()
        try SelfTests.check(find(window,"task.activity") != nil && find(window,"task.stop") == nil,"contact loading never presents a send cancellation action")
        model.busy=false; model.engine.busy=false
        try await pause()
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
        window.makeFirstResponder(nil); try await pause(); NSApp.mainMenu?.update()
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
        try await click(window,id:"sidebar.联系人")
        window.setContentSize(NSSize(width:900,height:690))
        try model.commit { $0.account=nil; $0.contacts=[]; $0.selected=[]; $0.plan.enabled=false }
        try await pause()
        for id in ["account.login","contacts.selectAll"] {
            guard let element=find(window,id), let frame=(attribute(element,"accessibilityFrame") as? NSValue)?.rectValue else { throw PrototypeError.message("Missing empty-list control: \(id)") }
            try SelfTests.check(frame.minY >= window.frame.minY && frame.maxY <= window.frame.maxY,"empty-list control \(id) remains inside a compact window")
        }
        window.performClose(nil); try await pause()
        try SelfTests.check(NSApp.activationPolicy() == .accessory,"red close button returns to menu-bar mode")
        try? FileManager.default.removeItem(at:model.store.directory)
    }
}
