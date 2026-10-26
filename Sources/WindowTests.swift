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
    static func sidebarBackdrop(_ root:NSView) -> NSVisualEffectView? {
        if let backdrop=root as? NSVisualEffectView, backdrop.identifier?.rawValue == "sidebar.backdrop" { return backdrop }
        for child in root.subviews { if let backdrop=sidebarBackdrop(child) { return backdrop } }
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
    static func clickNative(_ window:NSWindow, button:NSButton) async throws {
        let point=button.convert(NSPoint(x:button.bounds.midX,y:button.bounds.midY),to:nil)
        guard let root=window.contentView?.superview,
              root.hitTest(root.convert(point,from:nil)) === button else {
            throw PrototypeError.message("Native window button is outside its hit region")
        }
        // Native titlebar widgets have a separate AppKit tracking loop. Verify
        // their real hit target, then exercise the corresponding window action.
        if button === window.standardWindowButton(.miniaturizeButton) { window.miniaturize(nil) }
        else if button === window.standardWindowButton(.closeButton) { window.performClose(nil) }
        else if button === window.standardWindowButton(.zoomButton), let action=button.action {
            try SelfTests.check(NSApp.sendAction(action,to:button.target,from:button),"green control dispatches its configured height action")
        }
        try await pause()
    }
    static func checkWindowControls(_ window:NSWindow) throws {
        for type in [NSWindow.ButtonType.closeButton,.miniaturizeButton,.zoomButton] {
            guard let button=window.standardWindowButton(type) else { throw PrototypeError.message("Native window button missing") }
            let frame=window.convertToScreen(button.convert(button.bounds,to:nil))
            try SelfTests.check(abs(frame.minX-window.frame.minX-(type == .closeButton ? 18 : type == .miniaturizeButton ? 38 : 58)) < 1 && abs(window.frame.maxY-frame.maxY-18) < 1,"native \(type == .closeButton ? "close" : type == .miniaturizeButton ? "minimize" : "height zoom") button keeps an 18-point corner inset")
        }
    }
    static func run(_ delegate:AppDelegate) async throws {
        DispatchQueue.main.asyncAfter(deadline:.now()+55) { fputs("FAIL: native window test timeout\n",stderr); exit(1) }
        try await pause()
        let window=delegate.window!, model=delegate.model!
        let probe=NSWindow(contentRect:NSRect(x:100,y:100,width:300,height:240),styleMask:[.titled,.miniaturizable],backing:.buffered,defer:false)
        probe.isReleasedWhenClosed=false; probe.makeKeyAndOrderFront(nil)
        try await pause(); probe.miniaturize(nil)
        try await Task.sleep(for:.seconds(1))
        let minimizationAvailable=probe.isMiniaturized
        probe.close(); delegate.show(); try await pause()
        try SelfTests.check(window.isVisible && NSApp.activationPolicy() == .regular,"visible main window uses regular Dock application policy")
        try SelfTests.check(find(window,"account.logout.sidebar") != nil,"sidebar exposes logout beside the account name")
        try checkWindowControls(window)
        try SelfTests.check(window.standardWindowButton(.zoomButton)?.isHidden == false && window.standardWindowButton(.zoomButton)?.isEnabled == true,"green height control is visible and enabled")
        try SelfTests.check(window.collectionBehavior.contains(.fullScreenNone) && window.collectionBehavior.contains(.fullScreenDisallowsTiling),"main window opts out of fullscreen and split-screen tiling")
        let originalFrame=window.frame
        window.toggleFullScreen(nil)
        try await pause()
        try SelfTests.check(!window.styleMask.contains(.fullScreen) && window.frame == originalFrame,"fullscreen remains disabled")
        guard let green=window.standardWindowButton(.zoomButton), let workArea=window.screen?.visibleFrame else { throw PrototypeError.message("Green control or work area missing") }
        try await clickNative(window,button:green)
        try SelfTests.check(abs(window.frame.minY-workArea.minY)<1 && abs(window.frame.maxY-workArea.maxY)<1 && window.frame.width==originalFrame.width && window.frame.minX==originalFrame.minX,"green control fills the usable screen height while preserving width and horizontal position")
        try SelfTests.check(window.isZoomed && !window.styleMask.contains(.fullScreen) && green.toolTip == "恢复窗口高度","height zoom stays on the desktop and updates the green control label")
        try checkWindowControls(window)
        try await clickNative(window,button:green)
        try SelfTests.check(window.frame==originalFrame && !window.isZoomed,"second green press restores the previous height and position")
        window.performZoom(nil); window.zoom(nil)
        try SelfTests.check(window.frame==originalFrame,"menu and native zoom actions use the same reversible height behavior")
        window.setContentSize(NSSize(width:originalFrame.width,height:SparkyMainWindow.minimumContentSize.height))
        let manuallyResized=window.frame
        window.performZoom(nil); window.performZoom(nil)
        try SelfTests.check(window.frame==manuallyResized,"height restore honors a manually resized normal window")
        window.setFrame(originalFrame,display:true)
        window.setContentSize(NSSize(width:300,height:200))
        try await pause()
        try SelfTests.check(window.contentView!.bounds.width >= 940 && window.contentView!.bounds.height >= 760,"undersized content requests are clamped to the readable minimum")
        window.setFrame(NSRect(x:originalFrame.minX,y:originalFrame.maxY-240,width:320,height:240),display:true)
        try SelfTests.check(window.frame.width >= window.minSize.width && window.frame.height >= window.minSize.height,"frame resizing cannot bypass the minimum")
        window.setFrame(NSRect(x:originalFrame.minX,y:originalFrame.maxY-240,width:320,height:240),display:true,animate:false)
        let liveSize=delegate.windowWillResize(window,to:NSSize(width:320,height:240))
        try SelfTests.check(window.frame.width >= window.minSize.width && liveSize.width >= window.minSize.width && liveSize.height >= window.minSize.height,"animated and live resize paths enforce the same minimum")
        try await pause()
        try checkWindowControls(window)
        for id in ["plan.message","plan.time","plan.recipients","plan.run"] {
            guard let element=find(window,id), let frame=(attribute(element,"accessibilityFrame") as? NSValue)?.rectValue else { throw PrototypeError.message("Missing plan control: \(id)") }
            try SelfTests.check(frame.minX >= window.frame.minX && frame.maxX <= window.frame.maxX && frame.minY >= window.frame.minY && frame.maxY <= window.frame.maxY,"minimum window keeps \(id) in view")
        }
        if let recipient=find(window,"plan.recipients"), let run=find(window,"plan.run"),
           let r=(attribute(recipient,"accessibilityFrame") as? NSValue)?.rectValue,
           let b=(attribute(run,"accessibilityFrame") as? NSValue)?.rectValue {
            try SelfTests.check(r.minY > b.maxY,"recipient selection remains above the fixed send footer at minimum size")
        }
        window.setFrame(originalFrame,display:true)
        try await pause()
        try SelfTests.check(window.toolbar == nil && window.titlebarAppearsTransparent && !window.isOpaque,"window uses a transparent title bar without an empty toolbar band")
        if let backdrop=sidebarBackdrop(window.contentView!) {
            try SelfTests.check(backdrop.blendingMode == .behindWindow && backdrop.material == .sidebar && backdrop.alphaValue == 1 && backdrop.state == .followsWindowActiveState,"sidebar uses standard system sidebar opacity and activation behavior")
        } else {
            try SelfTests.check(NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,"a solid sidebar is used when reduced transparency is requested")
        }
        guard let title=find(window,"page.title"), let titleFrame=(attribute(title,"accessibilityFrame") as? NSValue)?.rectValue else { throw PrototypeError.message("Page title missing") }
        try SelfTests.check(window.frame.maxY-titleFrame.maxY < 65,"page content begins at the top without the old gray header band")
        let selectionBeforeFold=model.saved.selected
        let preferenceBefore=UserDefaults.standard.object(forKey:"Sparky.sidebarCollapsed") as? Bool
        try await click(window,id:"sidebar.toggle")
        guard let compactItem=find(window,"sidebar.联系人"), let compactFrame=(attribute(compactItem,"accessibilityFrame") as? NSValue)?.rectValue else { throw PrototypeError.message("Collapsed navigation missing") }
        try SelfTests.check(compactFrame.width >= 40 && compactFrame.width <= 64,"collapsed sidebar retains generous icon-only hit areas")
        try SelfTests.check(attribute(compactItem,"accessibilityLabel") as? String == "联系人","icon-only navigation retains an accessible name")
        if let toggle=find(window,"sidebar.toggle"), let toggleFrame=(attribute(toggle,"accessibilityFrame") as? NSValue)?.rectValue,
           let close=window.standardWindowButton(.closeButton) {
            let closeFrame=window.convertToScreen(close.convert(close.bounds,to:nil))
            try SelfTests.check(!toggleFrame.intersects(closeFrame),"sidebar toggle leaves the native window controls unobstructed")
        }
        try await click(window,id:"sidebar.设置")
        try SelfTests.check(find(window,"account.logout.settings") != nil,"collapsed navigation still opens the settings page")
        try await click(window,id:"account.settings")
        try SelfTests.check(model.saved.selected == selectionBeforeFold,"collapsing and account navigation preserve recipients")
        model.busy=true
        try await click(window,id:"sidebar.toggle")
        guard let expandedItem=find(window,"sidebar.联系人"), let expandedFrame=(attribute(expandedItem,"accessibilityFrame") as? NSValue)?.rectValue else { throw PrototypeError.message("Expanded navigation missing") }
        try SelfTests.check(expandedFrame.width > 140 && model.busy,"sidebar can expand during an ongoing task")
        model.busy=false
        try SelfTests.check((UserDefaults.standard.object(forKey:"Sparky.sidebarCollapsed") as? Bool) == preferenceBefore,"offline UI tests do not alter the user's sidebar preference")
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
        try await click(window,id:"sidebar.toggle")
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
        try SelfTests.check(find(window,"sidebar.toggle").flatMap { attribute($0,"accessibilityValue") as? String } == "已折叠","reopening the main window retains the collapsed sidebar")
        guard let minimize=window.standardWindowButton(.miniaturizeButton) else { throw PrototypeError.message("Minimize button missing") }
        try await clickNative(window,button:minimize)
        try await Task.sleep(for:.seconds(1))
        if minimizationAvailable {
            try SelfTests.check(window.isMiniaturized,"inset minimize hit target and native action remain available")
        } else {
            print("SKIP: minimization acknowledgement unavailable in this session; an unmodified NSWindow also cannot minimize")
            try SelfTests.check(window.styleMask.contains(.miniaturizable) && minimize.isEnabled,"native minimize control and style remain enabled")
        }
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
        try checkWindowControls(window)
        guard let close=window.standardWindowButton(.closeButton) else { throw PrototypeError.message("Close button missing") }
        try await clickNative(window,button:close)
        try SelfTests.check(NSApp.activationPolicy() == .accessory,"red close button returns to menu-bar mode")
        try? FileManager.default.removeItem(at:model.store.directory)
    }
}
