import AppKit
import CryptoKit
import ImageIO
import SwiftUI

// Avatar URLs come from a remote page. Do not let them become arbitrary native
// requests to local services, files, or unrelated sites, including redirects.
enum AvatarURLPolicy {
    static func url(_ value:String?) -> URL? {
        guard let value, value.count <= 4096, let u=URL(string:value),
              u.scheme == "https", u.user == nil, u.password == nil,
              u.port == nil || u.port == 443, let host=u.host?.lowercased(),
              ["douyinpic.com","douyincdn.com","byteimg.com","pstatp.com","ibytedtos.com"].contains(where:{host == $0 || host.hasSuffix("."+$0)}) else { return nil }
        return u
    }
}

private final class AvatarTransport: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session:URLSession, task:URLSessionTask, willPerformHTTPRedirection response:HTTPURLResponse, newRequest request:URLRequest, completionHandler:@escaping (URLRequest?) -> Void) {
        completionHandler(AvatarURLPolicy.url(request.url?.absoluteString) == nil ? nil : request)
    }
}

@MainActor
final class AvatarCache {
    static let shared=AvatarCache()
    private let memory=NSCache<NSString,NSImage>()
    private var pending:[String:Task<NSImage?,Never>]=[:]
    private let directory:URL
    private let fetch:@Sendable (URL) async throws -> Data
    private var active=0
    private var waiting:[CheckedContinuation<Void,Never>]=[]
    private var writes=0
    init(directory:URL?=nil, fetch:(@Sendable (URL) async throws -> Data)?=nil) {
        self.directory=directory ?? FileManager.default.urls(for:.cachesDirectory,in:.userDomainMask)[0].appendingPathComponent("Sparky/Avatars")
        memory.countLimit=256; memory.totalCostLimit=8*1024*1024
        if let fetch { self.fetch=fetch }
        else {
            let config=URLSessionConfiguration.ephemeral
            config.httpShouldSetCookies=false; config.httpCookieStorage=nil
            config.urlCache=nil; config.httpMaximumConnectionsPerHost=3
            config.timeoutIntervalForRequest=10; config.timeoutIntervalForResource=15
            let session=URLSession(configuration:config,delegate:AvatarTransport(),delegateQueue:nil)
            self.fetch={ url in
                let (data,response)=try await session.data(for:URLRequest(url:url))
                guard let http=response as? HTTPURLResponse, http.statusCode == 200,
                      AvatarURLPolicy.url(http.url?.absoluteString) != nil,
                      http.mimeType?.hasPrefix("image/") == true, data.count <= 2*1024*1024 else { throw URLError(.badServerResponse) }
                return data
            }
        }
    }
    private func acquire() async {
        if active < 3 { active += 1; return }
        await withCheckedContinuation { waiting.append($0) }
    }
    private func release() {
        if waiting.isEmpty { active -= 1 } else { waiting.removeFirst().resume() }
    }
    private func thumbnail(_ data:Data) -> NSImage? {
        guard data.count <= 2*1024*1024,
              let source=CGImageSourceCreateWithData(data as CFData,nil),
              let cg=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:96,kCGImageSourceCreateThumbnailWithTransform:true] as CFDictionary) else { return nil }
        return NSImage(cgImage:cg,size:NSSize(width:cg.width,height:cg.height))
    }
    func image(for value:String?) async -> NSImage? {
        guard let url=AvatarURLPolicy.url(value) else { return nil }
        let key=SHA256.hash(data:Data(url.absoluteString.utf8)).map{String(format:"%02x",$0)}.joined()
        if let image=memory.object(forKey:key as NSString) { return image }
        if let task=pending[key] { return await task.value }
        let task=Task<NSImage?,Never> { [self] in
            let file=directory.appendingPathComponent(key+".png")
            if let attrs=try? FileManager.default.attributesOfItem(atPath:file.path),
               let modified=attrs[.modificationDate] as? Date, Date().timeIntervalSince(modified) < 30*86400,
               let data=try? Data(contentsOf:file), let image=thumbnail(data) {
                memory.setObject(image,forKey:key as NSString,cost:96*96*4); return image
            }
            await acquire(); defer { release() }
            guard let data=try? await fetch(url), let image=thumbnail(data) else { return nil }
            memory.setObject(image,forKey:key as NSString,cost:96*96*4)
            if let cg=image.cgImage(forProposedRect:nil,context:nil,hints:nil), let png=NSBitmapImageRep(cgImage:cg).representation(using:.png,properties:[:]) {
                do {
                    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
                    try png.write(to:file,options:.atomic)
                    try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:file.path)
                    writes += 1; if writes % 16 == 1 { prune() }
                } catch { /* A cache failure must not block contacts or sending. */ }
            }
            return image
        }
        pending[key]=task
        let image=await task.value
        pending.removeValue(forKey:key)
        return image
    }
    private func prune() {
        let files=(try? FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:[.contentModificationDateKey],options:.skipsHiddenFiles)) ?? []
        let sorted=files.filter{$0.pathExtension == "png"}.sorted { ((try? $0.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast) > ((try? $1.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
        for file in sorted.dropFirst(512) { try? FileManager.default.removeItem(at:file) }
    }
}

@MainActor
struct ContactAvatar: View {
    let contact:Contact
    @StateObject private var image=AvatarImage()
    var body:some View {
        ZStack {
            Circle().fill(contact.group ? Color.blue.opacity(0.10) : Color.orange.opacity(0.10))
            if let value=image.value { Image(nsImage:value).resizable().scaledToFill() }
            else if contact.group { Image(systemName:"person.2.fill").foregroundStyle(.blue) }
            else { Text(String(contact.title.prefix(1))).font(.headline).foregroundStyle(.orange) }
        }.frame(width:38,height:38).clipShape(Circle()).accessibilityHidden(true)
        .task(id:contact.avatarURL) {
            image.value=nil
            guard let url=contact.avatarURL else { return }
            let loaded=await AvatarCache.shared.image(for:url)
            guard !Task.isCancelled else { return }; image.value=loaded
        }
    }
}

@MainActor
private final class AvatarImage: ObservableObject {
    @Published var value:NSImage?
}
