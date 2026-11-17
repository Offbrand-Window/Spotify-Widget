# Validation — version 1.9 (10)

- Release build and deep app/extension signatures passed.
- Custom AppIcon.icns included in app and extension; setup-window logo visually inspected.
- Persistent NSStatusItem creation removed; LSUIElement/accessory mode retains no Dock icon. Settings remain reachable through Applications and widget URL.
- Local-art regression tests passed: failed lookup retry; next with reused ID; back with missing ID; successful cache reuse; embedded image priority over Spotify URL changes; transient album recovery. Request-generation token also guards A→B→A cancellation races.
- Live Spotify next/back test passed: forward navigation advanced with a cover present; returning to the local original restored its embedded cover. Original track and play/pause state were restored.
- Buttons now have near-opaque backing, high-contrast outlines, and separately rasterized full-white bold symbols. Updated Medium layout preview visually checked.
- Animated-cover support was rechecked against Apple’s WidgetKit documentation: looping video is unsupported; data-update animations are limited to two seconds. No nonfunctional fourth mode was added.

Remaining limit: not every song/file-format and every desktop size/control combination has an end-to-end integration check.

Earlier integration checks also verified native desktop Play/Pause, buffered HTTP headers, synthetic MP3 embedded artwork extraction, mismatched artist rejection, grayscale on/off, album tint on/off, and text bitmap bounds with accented letters and descenders. All three sizes were checked in offscreen previews.
