import AppKit

@MainActor
enum ContactScanTests {
    static func run() async throws {
        let engine = try BrowserEngine(selfTest: true)
        defer { engine.stop() }
        try engine.start(show: false)
        _ = try await engine.accountInfo()
        _ = try await engine.evaluate("""
        window.hydratedAt=0;
        const items=[...document.querySelectorAll('[data-e2e=conversation-item]')];
        for(const [i,el] of items.entries()){
          el.querySelector('.conversationConversationItemtitle').textContent=String(4163172798306419+i);
          el.querySelector('img').removeAttribute('src');
        }
        setTimeout(()=>{for(const [i,el] of items.entries())el.querySelector('.conversationConversationItemtitle').textContent='加载完成 '+i;},1800);
        setTimeout(()=>{for(const [i,el] of items.entries())el.querySelector('img').src='https://p3-pc.douyinpic.com/hydrated-'+i+'.png';window.hydratedAt=Date.now();},2700);
        true
        """)
        let hydrated = try await engine.scan()
        let hydratedAt = try await engine.evaluate("window.hydratedAt") as? Double ?? 0
        try SelfTests.check(hydrated.count == 2 && hydrated.allSatisfy { $0.title.hasPrefix("加载完成") && $0.avatarURL?.contains("hydrated-") == true } && hydratedAt > 0, "scan waits for delayed participant names and avatar addresses instead of publishing numeric fallbacks")
        let sent = try await engine.evaluate("window.fixtureSent") as? Int
        try SelfTests.check(sent == 0, "contact hydration never clicks a conversation send button")

        engine.stop(); try engine.start(show: false); _ = try await engine.accountInfo()
        _ = try await engine.evaluate("""
        const sc=document.querySelector('.conversationConversationListwrapper');
        const items=[...document.querySelectorAll('[data-e2e=conversation-item]')];let scanOffset=0,page=-1;
        Object.defineProperties(sc,{clientHeight:{get:()=>200},scrollHeight:{get:()=>400},scrollTop:{get:()=>scanOffset}});
        function render(next){if(page===next)return;page=next;
          for(const [i,el] of items.entries()){
            const c=el.__reactProps$fixture.conversation;c.id=next?'late-'+i:'first-'+i;
            el.querySelector('.conversationConversationItemtitle').textContent=next?String(1786020291674222+i):'首页 '+i;
            if(next)el.querySelector('img').removeAttribute('src');else el.querySelector('img').src='https://p3-pc.douyinpic.com/first-'+i+'.png';
          }
          if(next)setTimeout(()=>{if(page!==1)return;for(const [i,el] of items.entries()){
            el.querySelector('.conversationConversationItemtitle').textContent='第二页 '+i;
            el.querySelector('img').src='https://p3-pc.douyinpic.com/late-'+i+'.png';
          }},1600);
        }
        sc.scrollTo=({top:value})=>{scanOffset=Math.max(0,Math.min(200,value));render(scanOffset>0?1:0);};render(0);true
        """)
        let paged = try await engine.scan()
        try SelfTests.check(paged.count == 4 && paged.filter { $0.id.hasPrefix("late-") }.allSatisfy { $0.title.hasPrefix("第二页") && $0.avatarURL != nil }, "virtualized later pages receive the same hydration checks as the initial list")

        engine.stop(); try engine.start(show: false)
        let account = try await engine.accountInfo()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sparky-scan-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LocalStore(directory: root), model = SparkyModel(store: LocalStore(directory: root), engine: engine, testing: true)
        let cached = Contact(id: "test-a", title: "原本的好友", group: false, avatarURL: "https://p3-pc.douyinpic.com/cached.png")
        try model.applyContacts([cached], account: account); model.toggleContact(cached.id)
        _ = try await engine.evaluate("""
        for(const el of document.querySelectorAll('[data-e2e=conversation-item]')){
          el.querySelector('.conversationConversationItemtitle').textContent='96704381246';el.querySelector('img').removeAttribute('src');
        }true
        """)
        var rejected = false
        do { try await model.synchronizeContacts(account: account, readinessTimeout: 0.8) } catch { rejected = true }
        let persisted = try store.load()
        try SelfTests.check(rejected && model.logs.filter { $0.contains("自动补读") }.count == 1, "persistently incomplete profiles receive exactly one bounded reread before failing")
        try SelfTests.check(persisted.contacts == [cached] && persisted.selected == [cached.id] && persisted.selectionsByAccount?[account.uid] == [cached.id], "failed hydration preserves the previous names, avatars and account selections on disk")

        // A numeric nickname with a real avatar is valid; a named contact may
        // legitimately have no supported avatar. Do not wait on image bytes.
        _ = try await engine.evaluate("""
        for(const [i,el] of [...document.querySelectorAll('[data-e2e=conversation-item]')].entries()){
          el.querySelector('.conversationConversationItemtitle').textContent=i?'没有头像的好友':'1234567890';
          if(!i)el.querySelector('img').src='https://p3-pc.douyinpic.com/numeric.png';
        }true
        """)
        let legitimate = try await engine.scan()
        try SelfTests.check(legitimate[0].title == "1234567890" && legitimate[1].title == "没有头像的好友" && legitimate[1].avatarURL == nil, "numeric nicknames with avatars and named contacts without avatars remain supported")
        _ = try await engine.evaluate("document.querySelector('.conversationConversationItemtitle').textContent='';true")
        let raw = try await engine.call("rows") as? [[String:Any]]
        try SelfTests.check(raw?.first?["title"] as? String == "" && raw?.first?["profilePending"] as? Bool == true, "the page bridge marks missing names as pending rather than inventing numbered conversation titles")
    }
}
