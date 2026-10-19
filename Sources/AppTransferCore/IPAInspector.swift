import Foundation
import CryptoKit
import ArchiveBridge

public struct IPAInspection: Sendable {
    public let app: AppDescriptor
    public let hasSinf: Bool
    public let bytes: Int64
    public let sha256: String
    public let icon: Data?
}

public enum IPAInspector {
    public static func inspect(_ url: URL, expected: AppDescriptor? = nil) throws -> IPAInspection {
        var info=ATArchiveInfo(); var error: UnsafeMutablePointer<CChar>?
        guard at_archive_inspect(url.path,&info,&error)==0 else { defer {at_archive_free(error)}; throw AppFailure("invalidArchive",error.map{String(cString:$0)} ?? "Invalid IPA archive") }
        defer {at_archive_info_free(&info)}
        let data=Data(bytes:info.info,count:info.info_length)
        guard let plist=try PropertyListSerialization.propertyList(from:data,format:nil) as? [String:Any], let bundle=plist["CFBundleIdentifier"] as? String, !bundle.isEmpty else {throw AppFailure("invalidArchive","The IPA has no application identifier.")}
        var metadata: [String:Any]=[:]
        if let pointer=info.metadata, info.metadata_length>0 { metadata=(try? PropertyListSerialization.propertyList(from:Data(bytes:pointer,count:info.metadata_length),format:nil)) as? [String:Any] ?? [:] }
        let account=(metadata["com.apple.iTunesStore.downloadInfo"] as? [String:Any])?["accountInfo"] as? [String:Any]
        let app=AppDescriptor(bundleID:bundle,name:plist["CFBundleDisplayName"] as? String ?? plist["CFBundleName"] as? String ?? bundle,version:stringValue(plist["CFBundleShortVersionString"]) ?? "",build:stringValue(plist["CFBundleVersion"]) ?? "",storeItemID:(metadata["itemId"] as? NSNumber)?.int64Value,externalVersionID:stringValue(metadata["softwareVersionExternalIdentifier"]),ownerEmail:account?["AppleID"] as? String ?? metadata["apple-id"] as? String ?? metadata["userName"] as? String,minimumOS:plist["MinimumOSVersion"] as? String,deviceFamilies:plist["UIDeviceFamily"] as? [Int] ?? [])
        if let expected {
            guard app.bundleID==expected.bundleID else {throw AppFailure("wrongBundle","Downloaded IPA does not match the selected application.")}
            guard expected.version.isEmpty || app.version==expected.version else {throw AppFailure("wrongVersion","Downloaded IPA does not match the requested version.")}
            guard expected.build.isEmpty || app.build==expected.build else {throw AppFailure("wrongVersion","Downloaded IPA does not match the requested build.")}
            if let expectedID=expected.externalVersionID, let actualID=app.externalVersionID, expectedID != actualID {throw AppFailure("wrongVersion","Downloaded IPA has a different App Store version identifier.")}
        }
        var iconData: Data?
        let icons=(plist["CFBundleIcons"] as? [String:Any])?["CFBundlePrimaryIcon"] as? [String:Any]
        let iconNames=(icons?["CFBundleIconFiles"] as? [String] ?? plist["CFBundleIconFiles"] as? [String] ?? []).reversed()
        if let root=info.app_path.map({String(cString:$0)}) {
            outer: for name in iconNames.prefix(3) {
                let base=name.hasSuffix(".png") ? String(name.dropLast(4)) : name
                for suffix in ["@3x.png","@2x.png",".png"] {
                    var bytes: UnsafeMutableRawPointer?;var count=0;var iconError:UnsafeMutablePointer<CChar>?
                    let result=at_archive_read_entry(url.path,"\(root)/\(base)\(suffix)",&bytes,&count,&iconError)
                    defer {at_archive_free(bytes);at_archive_free(iconError)}
                    if result==0,let bytes {iconData=Data(bytes:bytes,count:count);break outer}
                }
            }
        }
        let handle=try FileHandle(forReadingFrom:url);defer {try? handle.close()};var hasher=SHA256()
        while let chunk=try handle.read(upToCount:1024*1024),!chunk.isEmpty {hasher.update(data:chunk)}
        let hash=hasher.finalize().map{String(format:"%02x",$0)}.joined()
        let bytes=(try url.resourceValues(forKeys:[.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        return IPAInspection(app:app,hasSinf:info.has_sinf != 0,bytes:bytes,sha256:hash,icon:iconData)
    }
    private static func stringValue(_ value:Any?) -> String? { if let s=value as? String{return s};if let n=value as? NSNumber{return n.stringValue};return nil }
}
