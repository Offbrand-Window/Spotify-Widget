import WidgetKit
import SwiftUI
import AppIntents
import AppKit
import os

struct PlaybackIntent: AppIntent {
 static var title: LocalizedStringResource = "Control Spotify"
 static var openAppWhenRun = false
 @Parameter(title: "Action") var action: String
 init() { action = "toggle" }
 init(_ value: String) { action = value }
 func perform() async throws -> some IntentResult {
  guard await Bridge.request("command/" + action, post: true) != nil else { throw NSError(domain: "SpotifyWidget", code: 1, userInfo: [NSLocalizedDescriptionKey: "Open Spotify Widget in Applications to reconnect the background helper."]) }
  WidgetCenter.shared.reloadAllTimelines()
  return .result()
 }
}
enum WidgetLayout: String, AppEnum {
 case classic, artwork, ultraGlass
 static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Widget style")
 static var caseDisplayRepresentations: [WidgetLayout: DisplayRepresentation] = [.classic: "Default", .artwork: "Glass Album", .ultraGlass: "Ultra Glass"]
}
struct PlaylistConfiguration: WidgetConfigurationIntent {
 static var title: LocalizedStringResource = "Spotify Widget"
 static var description = IntentDescription("Choose a player style.")
 @Parameter(title: "Style", default: .classic) var style: WidgetLayout
}
struct Entry: TimelineEntry { let date: Date; let state: Snapshot; var style: WidgetLayout = .classic }
struct Provider: AppIntentTimelineProvider {
 func placeholder(in context: Context) -> Entry { Entry(date: .now, state: .empty) }
 func snapshot(for configuration: PlaylistConfiguration, in context: Context) async -> Entry {
  let state = await Bridge.snapshot()
  let style = state.styleOverride.flatMap { WidgetLayout(rawValue: $0) } ?? configuration.style
  Logger(subsystem: "com.arjun.spotifywidget.controls", category: "Timeline").notice("Requested style: \(configuration.style.rawValue, privacy: .public); rendered style: \(style.rawValue, privacy: .public)")
  return Entry(date: .now, state: state, style: style)
 }

 func timeline(for configuration: PlaylistConfiguration, in context: Context) async -> Timeline<Entry> { let entry = await snapshot(for: configuration, in: context); return Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(60))) }
}
struct NativeWidgetView: View {
 @Environment(\.widgetFamily) var family
 let entry: Entry
 var state: Snapshot { entry.state }
 var displayTitle: String { state.message == nil ? state.title : "Spotify needs attention" }
 var displayArtist: String { state.message == nil ? state.artist : "Tap ••• to check setup" }
 var accentColor: ArtworkTint {
  guard state.tintedText == true, let tint = state.textTint else { return .neutral }
  if state.grayscale == true {
   let gray = 0.2126 * tint.red + 0.7152 * tint.green + 0.0722 * tint.blue
   return ArtworkTint(red: gray, green: gray, blue: gray)
  }
  return tint
 }
 @ViewBuilder func label(_ text: String, size: CGFloat, strong: Bool = false, lines: Int = 1) -> some View {
  if ultraGlass || state.tintedText == true || state.backContrast == true {
   CrispWidgetText(text: text, size: size, strong: strong, lines: lines, color: state.tintedText == true ? accentColor : .neutral, boxed: state.backContrast == true)
  } else {
   Text(text).font(.system(size: size, weight: strong ? .semibold : .regular)).lineLimit(lines).help(text)
  }
 }
 var ultraGlass: Bool { entry.style == .ultraGlass }
 var small: Bool { family == .systemSmall }
 var large: Bool { family == .systemLarge }
 var body: some View {
  Group {
   if entry.style == .artwork || ultraGlass { artworkLayout }
   else { classicLayout.padding(small ? 15 : family == .systemMedium ? 12 : 16) }
  }.containerBackground(.ultraThinMaterial, for: .widget).saturation((state.grayscale ?? false) ? 0 : 1)
 }
 var classicLayout: some View {
  VStack(alignment: .leading, spacing: small ? 6 : 10) {
   header
   if large {
    cover.frame(maxWidth: .infinity).frame(height: 176)
    details
    controls
    Spacer(minLength: 0)
   } else if family == .systemMedium {
    Spacer(minLength: 0)
    HStack(spacing: 12) {
     cover.frame(width: 76, height: 76)
     VStack(alignment: .leading, spacing: 6) { details; controls }.frame(maxWidth: .infinity)
    }
    Spacer(minLength: 0)
   } else {
    HStack(spacing: 10) { cover.frame(width: 44, height: 44); details }
    Spacer(minLength: 0)
    controls
   }
  }.foregroundStyle(.primary)
 }
 var header: some View {
  HStack(spacing: 6) {
   Image(systemName: "waveform").font(.system(size: 10, weight: .medium))
   label("Spotify", size: 11)
   Spacer()
   Link(destination: URL(string: "spotifywidget://setup")!) { Image(systemName: "ellipsis").frame(width: 20, height: 16) }.accessibilityLabel("Open Spotify widget settings")
  }.foregroundStyle(.secondary).frame(height: 16)
 }
 var details: some View {
  VStack(alignment: .leading, spacing: 1) {
   label(displayTitle, size: small ? 12 : large ? 18 : 13, strong: true, lines: 2)
   label(displayArtist, size: small ? 10 : 11).foregroundStyle(.secondary)
  }.frame(maxWidth: .infinity, alignment: .leading)
 }
 var controls: some View {
  HStack(spacing: small ? 4 : large ? 18 : 8) {
   GlassPlaybackButton(icon: "backward.end.fill", label: "Previous song", action: "previous", compact: small)
   GlassPlaybackButton(icon: "gobackward.10", label: "Rewind 10 seconds", action: "rewind", compact: small)
   GlassPlaybackButton(icon: state.playing ? "pause.fill" : "play.fill", label: state.playing ? "Pause" : "Play", action: "toggle", compact: small, prominent: true)
   GlassPlaybackButton(icon: "forward.end.fill", label: "Next song", action: "next", compact: small)
  }.frame(maxWidth: .infinity).frame(height: small ? 32 : 36)
 }
 var cover: some View {
  Group { if let data = state.artwork, let image = NSImage(data: data) { Image(nsImage: image).resizable().widgetAccentedRenderingMode(.fullColor).scaledToFit() } else { ZStack { Color.primary.opacity(0.045); Image(systemName: "music.note").foregroundStyle(.secondary) } } }.clipped().clipShape(RoundedRectangle(cornerRadius: 6)).accessibilityLabel("Album artwork")
 }
 var artworkLayout: some View {
  GeometryReader { geometry in
   ZStack {
    if let data = state.artwork, let image = NSImage(data: data) {
     if ultraGlass {
      if family == .systemMedium {
       Image(nsImage: image).resizable().widgetAccentedRenderingMode(.fullColor).scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).blur(radius: 24).clipped()
      } else {
       Image(nsImage: image).resizable().widgetAccentedRenderingMode(.fullColor).scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).clipped()
      }
     } else {
      let backdrop = (family == .systemMedium ? state.artworkBlurBackdrop : state.artworkBackdrop).flatMap { NSImage(data: $0) } ?? image
      Image(nsImage: backdrop).resizable().widgetAccentedRenderingMode(.fullColor).scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).clipped()
     }
    } else { Color.black.opacity(0.35) }

    if family == .systemMedium {
     HStack(spacing: 12) {
      cover.frame(width: geometry.size.height - 24, height: geometry.size.height - 24)
      VStack(alignment: .leading, spacing: 4) {
       header
       details
       Spacer(minLength: 0)
       controls
      }
     }.padding(12)
    } else {
     VStack(alignment: .leading, spacing: small ? 4 : 10) {
      header
      Spacer(minLength: small ? 0 : 40)
      VStack(alignment: .leading, spacing: 1) {
       label(displayTitle, size: small ? 12 : 21, strong: true, lines: 2)
       label(displayArtist, size: small ? 10 : 13).foregroundStyle(.white.opacity(0.75))
      }
      controls
     }.padding(small ? 12 : 16)
    }
   }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
    .foregroundStyle(.white).environment(\.colorScheme, .dark)
  }
 }
}
struct BrightButtonSymbol: View {
 let name: String
 let pointSize: CGFloat
 private var symbol: CGImage? {
  guard let source = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize, weight: .bold)) else { return nil }
  let size = NSSize(width: pointSize + 5, height: pointSize + 5)
  let output = NSImage(size: size)
  output.lockFocus()
  let rect = NSRect(origin: .zero, size: size)
  source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
  NSColor.white.setFill(); rect.fill(using: .sourceIn)
  output.unlockFocus()
  return output.cgImage(forProposedRect: nil, context: nil, hints: nil)
 }
 var body: some View {
  if let symbol {
   Image(decorative: symbol, scale: 2).resizable().widgetAccentedRenderingMode(.fullColor)
    .aspectRatio(contentMode: .fit).frame(width: pointSize + 3, height: pointSize + 3)
  }
 }
}
struct GlassPlaybackButton: View {
 @Environment(\.colorScheme) var colorScheme
 let icon: String
 let label: String
 let action: String
 var compact = false
 var prominent = false
 var body: some View {
  Button(intent: PlaybackIntent(action)) {
   ZStack {
    Circle().fill(colorScheme == .dark ? Color.black.opacity(prominent ? 0.94 : 0.86) : Color.white.opacity(prominent ? 0.78 : 0.64))
    Circle().fill(.ultraThinMaterial).glassEffect(.regular.tint(.black.opacity(0.30)).interactive(), in: .circle).opacity(0.35)
    Circle().strokeBorder(.primary.opacity(prominent ? 0.90 : 0.76), lineWidth: 1.2)
    BrightButtonSymbol(name: icon, pointSize: prominent ? (compact ? 15 : 18) : (compact ? 12 : 14))
   }.frame(width: compact ? 28 : 34, height: compact ? 28 : 34)
  }.buttonStyle(.plain).accessibilityLabel(label)
 }
}
@main struct SpotifyNativeWidget: Widget {
 let kind = "SpotifyNativeWidget"
 var body: some WidgetConfiguration {
  AppIntentConfiguration(kind: kind, intent: PlaylistConfiguration.self, provider: Provider()) { NativeWidgetView(entry: $0) }
   .configurationDisplayName("Spotify Widget")
   .description("Spotify playback with album artwork and glass controls.")
   .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
   .contentMarginsDisabled()
 }
}
