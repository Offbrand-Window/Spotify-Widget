import SwiftUI
import AppKit
import Network
import WidgetKit
import Combine
import CoreImage

final class Companion: NSObject, NSApplicationDelegate {
 let player = Player()
 var listener: NWListener?
 var window: NSWindow!
 var subscription: AnyCancellable?
 var lastKey = ""
 var textTint: ArtworkTint?
 var cachedGrayscale = false
 var cachedArtwork: NSImage?
 var coverData: Data?
 var backdropData: Data?
 var blurredBackdropData: Data?
 func applicationDidFinishLaunching(_ notification: Notification) {
  NSApp.setActivationPolicy(.accessory)
  let view = SetupView(player: player, onDone: { [weak self] in self?.window?.orderOut(nil) })
  window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 480), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
  window.title = "Spotify Widget · Setup"; window.isReleasedWhenClosed = false; window.contentView = NSHostingView(rootView: view); window.center()
  startServer(); player.start()
  subscription = player.$revision.dropFirst().debounce(for: .milliseconds(100), scheduler: RunLoop.main).sink { _ in
   WidgetCenter.shared.reloadTimelines(ofKind: "SpotifyNativeWidget")
  }
  if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let icon = NSImage(contentsOf: url) { NSApp.applicationIconImage = icon }
  show()
 }
 func updateArtworkCache() {
  let source = player.artwork
  if cachedArtwork === source && cachedGrayscale == player.grayscale { return }
  cachedArtwork = source; cachedGrayscale = player.grayscale; coverData = nil; backdropData = nil; blurredBackdropData = nil; textTint = nil
  guard let source else { return }
  textTint = ArtworkPalette.textTint(from: source)
  var image = source
  if player.grayscale, let bytes = source.tiffRepresentation, let input = CIImage(data: bytes) {
   let output = input.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
   let gray = NSImage(size: source.size); gray.addRepresentation(NSCIImageRep(ciImage: output)); image = gray
  }
  guard let tiff = image.tiffRepresentation, let original = NSBitmapImageRep(data: tiff) else { return }
  coverData = original.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
  let size = NSSize(width: 640, height: 640)
  func render(blurred: Bool) -> Data? {
   let canvas = NSImage(size: size)
   canvas.lockFocus()
   let rect = NSRect(origin: .zero, size: size)
   if blurred, let source = CIImage(data: tiff) {
    let output = source.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 24]).cropped(to: source.extent)
    let rendered = NSImage(size: image.size); rendered.addRepresentation(NSCIImageRep(ciImage: output)); rendered.draw(in: rect)
    NSColor.black.withAlphaComponent(0.80).setFill(); rect.fill()
   } else {
    let edge = min(image.size.width, image.size.height)
    image.draw(in: rect, from: NSRect(x: (image.size.width - edge)/2, y: (image.size.height - edge)/2, width: edge, height: edge), operation: .sourceOver, fraction: 1)
    NSGradient(colorsAndLocations: (NSColor.black.withAlphaComponent(0.94), 0), (NSColor.black.withAlphaComponent(0.84), 0.36), (NSColor.black.withAlphaComponent(0.30), 0.67), (NSColor.black.withAlphaComponent(0.08), 1))?.draw(in: rect, angle: 90)
   }
   canvas.unlockFocus()
   guard let data = canvas.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data) else { return nil }
   return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.82])
  }
  backdropData = render(blurred: false); blurredBackdropData = render(blurred: true)
 }
 func snapshot() -> Snapshot {
  updateArtworkCache()
  return Snapshot(title: player.title, artist: player.artist, playing: player.playing, connected: player.connected, artwork: coverData, message: player.message, styleOverride: player.styleOverride == "widget" ? nil : player.styleOverride, artworkBackdrop: backdropData, artworkBlurBackdrop: blurredBackdropData, grayscale: player.grayscale, backContrast: player.backContrast, tintedText: player.tintedText, textTint: textTint, artworkIsEmbedded: player.usingEmbeddedArtwork)
 }
 func startServer() {
  do {
   let params = NWParameters.tcp
   params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: 48763)
   let listener = try NWListener(using: params); self.listener = listener
   listener.newConnectionHandler = { [weak self] connection in
    connection.start(queue: .global(qos: .userInitiated))
    self?.receiveRequest(connection)
   }
   listener.start(queue: .global(qos: .userInitiated))
  } catch { player.message = "Could not start widget connection: \(error.localizedDescription)" }
 }
 func receiveRequest(_ connection: NWConnection, buffer: Data = Data()) {
  guard buffer.count < 65536 else { connection.cancel(); return }
  connection.receive(minimumIncompleteLength: 1, maximumLength: 65536 - buffer.count) { [weak self] data, _, complete, error in
   guard let self else { connection.cancel(); return }
   let full = buffer + (data ?? Data())
   guard full.range(of: Data("\r\n\r\n".utf8)) != nil else {
    if complete || error != nil { connection.cancel() } else { self.receiveRequest(connection, buffer: full) }
    return
   }
   guard let text = String(data: full, encoding: .utf8) else { connection.cancel(); return }
   let lines = text.components(separatedBy: "\r\n")
   guard lines.contains(where: { $0.lowercased() == "x-widget-token: \(Bridge.token)" }), let first = lines.first else { connection.cancel(); return }
   let parts = first.split(separator: " ")
   guard parts.count >= 2 else { connection.cancel(); return }
   let method = String(parts[0]), path = String(parts[1])
   DispatchQueue.main.async {
    let respond = {
     let body = (try? JSONEncoder().encode(self.snapshot())) ?? Data()
     let header = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
     connection.send(content: Data(header.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
    }
    if method == "POST", path.hasPrefix("/command/") { self.perform(String(path.dropFirst(9)), completion: respond) }
    else { respond() }
   }
  }
 }
 func perform(_ action: String, completion: @escaping () -> Void) {
  let command: String
  switch action {
  case "toggle": command = "playpause"
  case "previous": command = "previous track"
  case "next": command = "next track"
  case "rewind": command = "set p to (player position) - 10\nif p < 0 then set p to 0\nset player position to p"
  default: completion(); return
  }
  player.command(command) { WidgetCenter.shared.reloadTimelines(ofKind: "SpotifyNativeWidget"); completion() }
 }
 @objc func show() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
 @objc func quit() { NSApp.terminate(nil) }
 func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { show(); return false }
 func application(_ application: NSApplication, open urls: [URL]) { show() }
}
struct SetupView: View {
 @ObservedObject var player: Player
 var onDone: () -> Void = {}
 var body: some View {
  VStack(alignment: .leading, spacing: 16) {
   HStack(spacing: 10) { Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 36, height: 36); Text("Spotify Widget").font(.title2.weight(.semibold)) }
   Text("Right-click your desktop → Edit Widgets → Spotify Widget. Choose Small, Medium, or Large and drag it onto your desktop.").font(.callout).fixedSize(horizontal: false, vertical: true)
   Text("Runs in the background. Open this app or tap ••• for settings.").font(.caption).foregroundStyle(.secondary)
   HStack { Circle().fill(player.connected ? .green : .orange).frame(width: 7, height: 7); Text(player.connected ? "Connected to Spotify" : "Waiting for Spotify"); Spacer(); Button("Open Spotify") { player.openSpotify() } }.font(.callout)
   if let message = player.message { Text(message).font(.caption).foregroundStyle(.orange) }
   Picker("Widget appearance", selection: Binding(get: { player.styleOverride }, set: { player.setStyle($0) })) {
    Text("Use Edit Widget setting").tag("widget")
    Text("Default").tag("classic")
    Text("Glass Album").tag("artwork")
    Text("Ultra Glass").tag("ultraGlass")
   }
   Toggle("Back Contrast", isOn: Binding(get: { player.backContrast }, set: { player.setBackContrast($0) })).help("Switch between the letter-shaped backing and the black text box.")
   Toggle("Album-tinted text", isOn: Binding(get: { player.tintedText }, set: { player.setTintedText($0) })).help("Tint all text, including the song title, with a deeper album color.")
   Toggle("Grayscale", isOn: Binding(get: { player.grayscale }, set: { player.setGrayscale($0) })).help("Make the entire widget grayscale in any style.")
   Divider()
   HStack { Text("Local file artwork").font(.headline); Spacer(); Button("Add folder…") { player.addLocalFolders() } }
   Text(player.localArtworkStatus).font(.caption).foregroundStyle(.secondary)
   Text("Searches: " + player.localFolders.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
   HStack { Button("Quit Spotify Widget") { NSApp.terminate(nil) }.font(.caption); Spacer(); Button("Done", action: onDone).keyboardShortcut("w") }

  }.textFieldStyle(.roundedBorder).padding(24).frame(width: 460).preferredColorScheme(.dark)
 }
}
@main struct CompanionMain {
 static func main() { let app = NSApplication.shared; let delegate = Companion(); app.delegate = delegate; app.run() }
}
