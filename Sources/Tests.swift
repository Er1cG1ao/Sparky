import AppKit
import Foundation

@MainActor
enum SelfTests {
    static func check(_ condition: Bool, _ message: String) throws { if !condition { throw PrototypeError.message(message) }; print("PASS: \(message)") }
    static func run(_ model: SparkyModel) async throws {
        DispatchQueue.main.asyncAfter(deadline:.now()+180) { fputs("FAIL: test timeout\n",stderr); exit(1) }
        try await AvatarTests.run()
        try await LogoutTests.run()
        try await LoginTests.run()
        try await ContactScanTests.run()
        var calendar = Calendar(identifier:.gregorian); calendar.timeZone = TimeZone(identifier:"America/New_York")!
        func date(_ value:String) -> Date { let f=ISO8601DateFormatter(); return f.date(from:value)! }
        let morning = date("2026-10-23T12:00:00Z"), due=date("2026-10-23T13:00:00Z"), late=date("2026-10-23T20:00:00Z")
        var plan=DailyPlan(); plan.enabled=true; plan.hour=9; plan.enabledSince=morning
        try check(plan.due(at:morning,calendar:calendar)==nil,"schedule waits until due")
        try check(plan.due(at:due,calendar:calendar)==due,"schedule becomes due at exact minute")
        try check(plan.due(at:late,calendar:calendar)==due,"wake catches up only today's task")
        plan.lastScheduledDay=DailyPlan.day(due,calendar:calendar)
        try check(plan.due(at:late,calendar:calendar)==nil,"same-day task is not repeated")
        try check(plan.next(at:late,calendar:calendar)==date("2026-10-24T13:00:00Z"),"next task advances to tomorrow")
        plan.lastScheduledDay=nil; plan.enabledSince=late
        try check(plan.due(at:late,calendar:calendar)==nil && plan.next(at:late,calendar:calendar)==date("2026-10-24T13:00:00Z"),"enabling after due does not surprise-send")
        plan.hour=2; plan.minute=30; plan.enabledSince=date("2026-03-07T00:00:00Z")
        try check(plan.due(at:date("2026-03-08T08:00:00Z"),calendar:calendar) != nil,"DST skipped hour has a valid due time")
        plan.enabled=false; try check(plan.due(at:late,calendar:calendar)==nil,"disabled plan never runs")
        let e=model.engine
        try e.start(show:false)
        let account=try await e.accountInfo()
        let contacts=try await e.scan()
        try check(account.uid=="123456789" && contacts.count==2,"hidden WebKit reads account and two exact IDs")
        try check(!e.trustedURL(URL(string:"https://www.douyin.com.evil.invalid/chat")),"untrusted origin refused")
        try check(contacts[0].avatarURL == "https://p3-pc.douyinpic.com/fixture-a.png" && contacts[1].avatarURL == nil,"scan extracts each avatar and filters unsafe URLs")
        let a=contacts[0], b=contacts[1], text="离线测试 🔥"
        _ = try await e.evaluate("window.fixtureScrolls=0;const scroller=document.querySelector('.conversationConversationListwrapper');const scroll=scroller.scrollTo.bind(scroller);scroller.scrollTo=(...args)=>{window.fixtureScrolls++;return scroll(...args)};true")
        try await e.prepare(a,text:text)
        _ = try await e.evaluate("document.querySelector('[contenteditable]').textContent='\\u200B离线测试 🔥\\u200B'")
        try await e.prepare(a,text:text)
        var wrongTarget=false
        do { _ = try await e.send(b,text:text) } catch { wrongTarget=true }
        try check(wrongTarget,"wrong recipient blocked before dispatch")
        var blockedJournal=false
        do { _ = try await e.send(a,text:text,beforeDispatch:{ throw PrototypeError.message("simulate disk error") }) } catch { blockedJournal=true }
        let before=try await e.evaluate("window.fixtureSent") as? Int
        try check(blockedJournal && before==0,"journal failure prevents the click")
        let delivery=try await e.send(a,text:text)
        let once=try await e.evaluate("window.fixtureSent") as? Int
        try check(delivery.state == .confirmed && once==1,"SVG send fires exactly once and receives server ACK")
        var duplicate=false; do { _ = try await e.send(a,text:text) } catch { duplicate=true }
        try check(duplicate,"a consumed draft cannot be sent twice")
        let scrolls=try await e.evaluate("window.fixtureScrolls") as? Int
        try check(scrolls == 0,"visible recipients are selected without resetting or rescanning the list")
        let originalInput=e.selectors["JS_TYPE_LINE"]!
        e.selectors["JS_TYPE_LINE"]="(p)=>{setTimeout(()=>{document.querySelector('[contenteditable]').textContent=p.text},900);return true}"
        try await e.prepare(b,text:text)
        let delayed=try await e.call("inspectDraft",[b.id,text]) as? [String:Any]
        try check(delayed?["matches"] as? Bool == true,"adaptive input verification waits for a delayed editor update")
        e.selectors["JS_TYPE_LINE"]=originalInput
        _ = try await e.evaluate("document.querySelector('[contenteditable]').textContent='';true")
        try await e.select(a)
        // Previous receipts and an existing identical bubble cannot prove a new send.
        _ = try await e.evaluate("window.fetch=async()=>new Response(new Uint8Array());document.querySelector('[data-e2e=msg-send]').onclick=()=>{document.querySelector('[contenteditable]').textContent='';window.fixtureSent++};true")
        try await e.prepare(a,text:text)
        let ticket=try await e.call("send",[a.id,text]) as! [String:Any]
        let proof=try await e.call("proof",[a.id,text,ticket]) as! [String:Any]
        try check(proof["state"] as? String == "waiting" && proof["domSeen"] as? Bool == false,"old receipt and old matching bubble are excluded")
        e.stop()
        try e.start(show:false); _ = try await e.accountInfo()
        _ = try await e.evaluate("window.fixtureMode='reject'")
        try await e.prepare(a,text:text)
        let rejection=try await e.send(a,text:text)
        try check(rejection.state == .rejected,"server rejection is not reported as success")
        _ = try await e.evaluate("window.fetch=async()=>new Response(new Uint8Array());true")
        try await e.prepare(a,text:text)
        let pageOnly=try await e.send(a,text:text)
        try check(pageOnly.state == .pageOnly,"new outgoing bubble without ACK is page confirmation only")
        _ = try await e.evaluate("document.querySelector('[data-e2e=msg-send]').onclick=()=>{document.querySelector('[contenteditable]').textContent='';window.fixtureSent++};true")
        try await e.prepare(a,text:text)
        let unknown=try await e.send(a,text:text)
        try check(unknown.state == .uncertain,"no fresh evidence remains uncertain without retry")
        e.stop()
        try model.commit { s in s.account=account; s.contacts=contacts; s.selected=Set(contacts.map(\.id)); s.message=text }
        let loaded=try model.store.load()
        try check(loaded.selected.count==2 && loaded.message==text,"multi-selection and message survive store roundtrip")
        let batchStart=ContinuousClock.now
        await model.runBatch(scheduled:false)
        print("BENCHMARK: two offline contacts = \(batchStart.duration(to:.now)); excludes real network delays")
        let afterBatch=model.saved.history.count
        await model.runBatch(scheduled:true)
        try check(model.saved.history.count==afterBatch,"queued scheduler rechecks disabled or consumed plan")
        let records=model.saved.history
        try check(records.count==2 && records.allSatisfy{$0.state == .confirmed},"batch confirms two individual contacts")
        try check(!model.busy && e.webView==nil,"batch releases WebKit after completion")
        try check(model.saved.plan.lastScheduledDay==DailyPlan.day(Date()),"manual batch durably claims today's scheduled slot")
        let components=Calendar.current.dateComponents([.hour,.minute],from:Date())
        try model.commit { s in s.plan.enabled=true; s.plan.hour=components.hour!; s.plan.minute=components.minute!; s.plan.enabledSince=Calendar.current.startOfDay(for:Date()); s.plan.lastScheduledDay=nil }
        await model.runBatch(scheduled:true)
        try check(model.saved.history.count==4 && model.saved.history.suffix(2).allSatisfy{$0.state == .confirmed && $0.scheduled},"due daily plan executes a complete batch")
        await model.runBatch(scheduled:true)
        try check(model.saved.history.count==4,"completed daily plan cannot run twice")
        try model.commit { s in
            for state in [DeliveryState.queued,.preparing,.sending] {
                s.history.append(SendRecord(runID:UUID(),contactID:a.id,name:a.title,accountUID:account.uid,date:Date(),scheduled:true,state:state,detail:"interrupted"))
            }
        }
        let restored=SparkyModel(store:model.store,engine:try BrowserEngine(selfTest:true),testing:true)
        try check(restored.saved.history.suffix(3).map(\.state)==[.failed,.failed,.uncertain],"restart recovers unfinished records without resend")
        model.clearHistory()
        try check(model.saved.history.isEmpty && model.saved.plan.lastScheduledDay==DailyPlan.day(Date()),"clearing history does not rearm today's task")
        let permissions=try FileManager.default.attributesOfItem(atPath:model.store.file.path)[.posixPermissions] as? NSNumber
        try check(permissions?.intValue==0o600,"local state is owner-readable only")
        try? FileManager.default.removeItem(at:model.store.directory)
    }
}
