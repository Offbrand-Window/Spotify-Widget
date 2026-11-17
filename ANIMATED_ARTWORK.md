# Animated album artwork investigation

Taurus uses two sources: Spotify Canvas clips and Apple Music album motion artwork. Its source includes a Spotify client-authenticated Canvas request and an Apple Music catalog lookup. Those are different from Spotify desktop's static `artwork url` scripting property.

A native macOS WidgetKit widget cannot run an AVPlayer/looping video cover. Apple's supported view list excludes video-player views and AppKit wrappers, and widget update animations have a maximum duration of two seconds. Rapidly swapping movie frames through widget reloads would be unreliable and waste the widget's update budget.

This build therefore retains the genuine still album image, adds an artwork-focused layout, and uses supported controls. It does not claim to play a motion clip. The Apple Music public page inspected for Playboi Carti's MUSIC exposed null videoArtwork fields; that observation does not establish that every edition or catalog endpoint lacks motion artwork.

Sources:
- https://taurus.lat/
- https://gitlab.com/taurustweak/taurus/-/blob/HEAD/tweak/Sources/Shared/AnimatedArtwork/MotionSources.m
- https://gitlab.com/taurustweak/taurus/-/blob/HEAD/tweak/Sources/Shared/AnimatedArtwork/SGMotionCatalog.m
- https://developer.apple.com/documentation/widgetkit/swiftui-views
- https://developer.apple.com/documentation/widgetkit/animating-data-updates-in-widgets-and-live-activities
- https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date
