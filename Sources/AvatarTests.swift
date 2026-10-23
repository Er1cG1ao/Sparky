import AppKit

private actor AvatarFetchProbe {
    private(set) var hits=0
    func hit() { hits += 1 }
}

@MainActor
enum AvatarTests {
    static func run() async throws {
        let old=try JSONDecoder().decode(Contact.self,from:Data("{\"id\":\"legacy\",\"title\":\"旧联系人\",\"group\":false}".utf8))
        try SelfTests.check(old.avatarURL == nil,"legacy contacts without avatar fields still decode")
        let url="https://p3-pc.douyinpic.com/avatar-test.png"
        try SelfTests.check(AvatarURLPolicy.url(url) != nil,"known avatar CDN is accepted")
        try SelfTests.check(["http://127.0.0.1/a","file:///etc/hosts","https://douyinpic.com.evil.invalid/a","https://user:pass@p3-pc.douyinpic.com/a","https://p3-pc.douyinpic.com:123/a"].allSatisfy { AvatarURLPolicy.url($0) == nil },"native avatar requests reject local, unrelated and credential-bearing URLs")
        let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:2,pixelsHigh:2,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        for y in 0..<2 { for x in 0..<2 { let i=y*bitmap.bytesPerRow+x*4; let bytes=bitmap.bitmapData!; bytes[i]=255; bytes[i+1]=128; bytes[i+2]=0; bytes[i+3]=255 } }
        let png=bitmap.representation(using:.png,properties:[:])!
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("sparky-avatar-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at:directory) }
        let probe=AvatarFetchProbe()
        let cache=AvatarCache(directory:directory,fetch:{ _ in await probe.hit(); try await Task.sleep(nanoseconds:60_000_000); return png })
        let first=Task { @MainActor in await cache.image(for:url) }
        let second=Task { @MainActor in await cache.image(for:url) }
        let imageA=await first.value, imageB=await second.value
        let hits=await probe.hits
        try SelfTests.check(imageA != nil && imageB != nil && hits == 1,"simultaneous avatar requests are deduplicated and decoded")
        let files=try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil)
        try SelfTests.check(files.count == 1 && files[0].pathExtension == "png","only the decoded thumbnail is persisted")
        let permissions=try FileManager.default.attributesOfItem(atPath:files[0].path)[.posixPermissions] as? NSNumber
        try SelfTests.check(permissions?.intValue == 0o600,"cached avatar thumbnails are owner-readable only")
        let restored=AvatarCache(directory:directory,fetch:{ _ in throw URLError(.notConnectedToInternet) })
        let offlineImage=await restored.image(for:url)
        try SelfTests.check(offlineImage != nil,"cached avatars load after restart without network")
        let missing=await cache.image(for:"https://127.0.0.1/private")
        let afterInvalid=await probe.hits
        try SelfTests.check(missing == nil && afterInvalid == 1,"invalid avatar URLs never reach the network loader")
    }
}
