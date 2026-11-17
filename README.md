# Spotify Widget for macOS

Native desktop WidgetKit player in Small, Medium, and Large. Requires macOS 26+ and Spotify desktop; included Xcode project builds for Apple Silicon.

## Install the packaged app

Download **Spotify-Widget-1.9-macOS-arm64.zip** from this repository’s Releases page, unzip it, and move **Spotify Widget.app** to Applications. Open it once, allow access to control Spotify when macOS asks, then add it through desktop → Edit Widgets → Spotify Widget.

The packaged app is ad-hoc signed, not Developer ID signed or notarized. macOS may block a downloaded copy. You can build it locally with Xcode using **Build.command**; a distributable notarized build requires your own Apple Developer signing credentials.

## Build from source

Install Xcode and select its developer tools, then run **Build.command**. It builds both the helper and native widget extension and produces **Spotify Widget.app** beside the script. Builds target Apple Silicon and macOS 26 or newer. No Spotify API key is required.

The helper and extension communicate over a loopback-only connection. The shared bridge token is an application protocol constant, not a Spotify credential or a security boundary against software already running locally.

## Open settings

Open **Spotify Widget** in Applications or click the widget’s **•••** button. The app runs invisibly in the background, with no persistent menu-bar or Dock icon. **Done** hides settings; **Quit Spotify Widget** stops the background connection and playback controls.

To add a widget: right-click the desktop → Edit Widgets → Spotify Widget → choose a size.

## Playback and appearance

Controls: previous song, rewind 10 seconds, play/pause, next song. Buttons use near-opaque dark glass and bright white symbols.

Styles:
- Default: native glass player.
- Glass Album: larger artwork with a dark contrast backdrop.
- Ultra Glass: bright album artwork and crisp labels.

Independent switches:
- Back Contrast: black text boxes when on; letter-shaped black backing when off.
- Album-tinted text: all labels, including song titles, use a deeper, more saturated album-derived color.
- Grayscale: monochrome artwork and labels without changing the selected style or tint preference.

The helper’s appearance choice overrides individual Edit Widget style choices. Choose Use Edit Widget setting to restore per-widget choices. Playlist controls have been removed.

## Local-file covers

The app reads embedded artwork from matching local audio files in Music, Downloads, and any folders added under **Local file artwork → Add folder**. Title, artist, and album metadata identify the file.

Local lookup failures retry automatically. Successful covers are cached for next/back navigation, and Spotify image requests cannot overwrite an embedded cover. Artwork identity uses track metadata because local Spotify IDs can be reused or temporarily missing during skips. Outdated lookups are rejected by request-generation tokens.

Files are read locally and not uploaded. Audio files without embedded artwork use Spotify’s still cover or a neutral placeholder.

## Native platform limits

WidgetKit controls actual update scheduling, so a widget may refresh later than the background app. It does not support hover-triggered text marquees or looping video album covers. See ANIMATED_ARTWORK.md for the Apple Music/Spotify/Taurus investigation. No unsupported animated-cover mode is presented.

## Logo and source

Resources/AppIcon.icns is bundled with both the app and extension. Resources/AppIcon.png is the high-resolution logo; Source/MakeIcon.swift reproduces its vector drawing. Use Build.command or the included Xcode project to rebuild the app.

See VALIDATION.md for completed checks and remaining testing limits.
