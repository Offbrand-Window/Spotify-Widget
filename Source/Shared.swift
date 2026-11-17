import Foundation
struct ArtworkTint: Codable {
 var red: Double; var green: Double; var blue: Double
 static let neutral = ArtworkTint(red: 1, green: 1, blue: 1)
 var luminance: Double {
  func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
  return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
 }
}
struct Snapshot: Codable {
 var title: String; var artist: String; var playing: Bool; var connected: Bool; var artwork: Data?; var message: String?; var styleOverride: String? = nil; var artworkBackdrop: Data? = nil; var artworkBlurBackdrop: Data? = nil; var grayscale: Bool? = nil; var backContrast: Bool? = nil; var tintedText: Bool? = nil; var textTint: ArtworkTint? = nil; var artworkIsEmbedded: Bool? = nil
 static let empty = Snapshot(title: "Spotify on your desktop", artist: "Open Spotify Widget to connect", playing: false, connected: false, artwork: nil, message: nil)
}
enum Bridge {
 static let token = "9988dae4763a7c93b3b5344a24cf09687894539765e8d614958fed1789b7a47e"
 static func snapshot() async -> Snapshot {
  if let fresh = await request("state") {
   UserDefaults.standard.set(try? JSONEncoder().encode(fresh), forKey: "lastWidgetSnapshot")
   return fresh
  }
  if let data = UserDefaults.standard.data(forKey: "lastWidgetSnapshot"), let saved = try? JSONDecoder().decode(Snapshot.self, from: data) { return saved }
  return .empty
 }
 static func request(_ path: String, post: Bool = false) async -> Snapshot? {
  guard let url = URL(string: "http://127.0.0.1:48763/" + path) else { return nil }
  var req = URLRequest(url: url); req.timeoutInterval = post ? 12 : 4; req.httpMethod = post ? "POST" : "GET"; req.setValue(token, forHTTPHeaderField: "X-Widget-Token")
  guard let (data, response) = try? await URLSession.shared.data(for: req), (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
  return try? JSONDecoder().decode(Snapshot.self, from: data)
 }
}
