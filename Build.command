#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
xcodebuild -project SpotifyWidget.xcodeproj -target SpotifyWidget -configuration Release SYMROOT="$PWD/.build" build
/usr/bin/ditto '.build/Release/Spotify Widget.app' 'Spotify Widget.app'
print 'Built Spotify Widget.app. Move it into Applications, open it, then add the widget using Edit Widgets on the desktop.'
