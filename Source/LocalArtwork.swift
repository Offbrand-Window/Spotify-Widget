import Foundation
import AVFoundation
import CoreServices

enum LocalArtwork {
 static let extensions: Set<String> = ["mp3", "m4a", "mp4", "flac", "aif", "aiff", "wav", "aac"]
 static func normalized(_ value: String) -> String {
  value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")).unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
 }
 static func scan(_ folders: [String]) -> [URL] {
  var files: [URL] = []; var seen = Set<String>()
  for folder in folders {
   guard !Task.isCancelled else { return [] }
   let root = URL(fileURLWithPath: folder, isDirectory: true)
   guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
   for case let url as URL in enumerator {
    guard !Task.isCancelled else { return [] }
    if extensions.contains(url.pathExtension.lowercased()), seen.insert(url.standardizedFileURL.path).inserted { files.append(url) }
   }
  }
  return files
 }
 static func find(title: String, artist: String, album: String, folders: [String]) async -> Data? {
  let target = normalized(title), targetArtist = normalized(artist)
  guard !target.isEmpty else { return nil }
  let files = scan(folders)
  // File names and Spotlight tags prioritize likely matches; ID3/MP4 tags verify identity below.
  func rank(_ url: URL) -> Int {
   var score = normalized(url.deletingPathExtension().lastPathComponent).contains(target) ? 10 : 0
   if let item = MDItemCreate(nil, url.path as CFString), let name = MDItemCopyAttribute(item, kMDItemTitle) as? String, normalized(name) == target { score += 30 }
   return score
  }
  let ranked = files.map { ($0, rank($0)) }.sorted { $0.1 > $1.1 }.map(\.0)
  for url in ranked {
   guard !Task.isCancelled else { return nil }
   let asset = AVURLAsset(url: url)
   guard let metadata = try? await asset.load(.commonMetadata) else { continue }
   var fileTitle = "", fileArtist = "", fileAlbum = ""
   for item in metadata {
    switch item.commonKey {
    case .commonKeyTitle: fileTitle = (try? await item.load(.stringValue)) ?? ""
    case .commonKeyArtist: fileArtist = (try? await item.load(.stringValue)) ?? ""
    case .commonKeyAlbumName: fileAlbum = (try? await item.load(.stringValue)) ?? ""
    default: break
    }
   }
   let filename = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "^\\d+[ ._-]+", with: "", options: .regularExpression)
   let titleMatches = fileTitle.isEmpty ? normalized(filename) == target : normalized(fileTitle) == target
   guard titleMatches else { continue }
   let actualArtist = normalized(fileArtist)
   if !targetArtist.isEmpty && !actualArtist.isEmpty && actualArtist != targetArtist && !actualArtist.contains(targetArtist) && !targetArtist.contains(actualArtist) { continue }
   if !album.isEmpty && !fileAlbum.isEmpty && normalized(album) != normalized(fileAlbum) { continue }
   for item in metadata where item.commonKey == .commonKeyArtwork {
    if let data = try? await item.load(.dataValue), !data.isEmpty { return data }
   }
  }
  return nil
 }
}
