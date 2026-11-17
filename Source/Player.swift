import AppKit
import SwiftUI
import Combine

final class Player: ObservableObject {
    @Published var title = "Your music, right here."
    @Published var artist = "Open Spotify and press play"
    @Published var album = ""
    @Published var playing = false
    @Published var position = 0.0
    @Published var duration = 1.0
    @Published var artwork: NSImage?
    @Published var message: String?
    @Published var connected = false
    @Published var revision = 0
    @Published var backContrast = UserDefaults.standard.bool(forKey: "widgetBackContrast")
    @Published var tintedText = UserDefaults.standard.bool(forKey: "widgetTintedText")
    @Published var grayscale = UserDefaults.standard.bool(forKey: "widgetGrayscale")
    @Published var styleOverride = UserDefaults.standard.string(forKey: "widgetStyleOverride") ?? "widget"
    private var scriptingMessage: String?
    @Published var localFolders: [String] = UserDefaults.standard.stringArray(forKey: "localMusicFolders") ?? [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Music").path, FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads").path]
    @Published var localArtworkStatus = "Embedded artwork is read from local audio files."
    private var localArtworkTask: Task<Void, Never>?
    private var localTrackKey = ""
    private var embeddedArtworkKey = ""
    private var localRequest = UUID()
    private var localLookupRunning = false
    private var localRetryAt = Date.distantPast
    private var localAttempts = 0
    private var localCoverCache: [String: Data] = [:]
    private var remoteRequest = UUID()
    private let findLocalArtwork: (String, String, String, [String]) async -> Data?
    var usingEmbeddedArtwork: Bool { !embeddedArtworkKey.isEmpty && embeddedArtworkKey == lastTrackID }
    init(localArtworkFinder: @escaping (String, String, String, [String]) async -> Data? = { title, artist, album, folders in
        await LocalArtwork.find(title: title, artist: artist, album: album, folders: folders)
    }) { self.findLocalArtwork = localArtworkFinder }
    private let queue = DispatchQueue(label: "Spotify.scripting")
    private var busy = false
    private var timer: Timer?
    private var artURL = ""
    private var lastTrackID = ""
    private var artworkTask: URLSessionDataTask?
    private var playbackObserver: NSObjectProtocol?
    var preview = false
    func start() {
        refresh()
        playbackObserver = DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.spotify.client.PlaybackStateChanged"), object: nil, queue: .main) { [weak self] _ in self?.refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.refresh() }
    }
    static func script(_ source: String) -> (NSAppleEventDescriptor?, String?) {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            if code == -1743 { return (nil, "Allow Spotify control in System Settings → Privacy & Security → Automation.") }
            return (nil, error[NSAppleScript.errorMessage] as? String ?? "Spotify did not respond. Try again.")
        }
        return (result, nil)
    }
    func refresh(completion: (() -> Void)? = nil) {
        guard !preview else { completion?(); return }
        if busy && completion == nil { return }
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").first != nil else {
            let changed = connected || title != "Spotify is closed"
            connected = false; playing = false; title = "Spotify is closed"; artist = "Open Spotify to connect"; artwork = nil; artURL = ""; artworkTask?.cancel(); localArtworkTask?.cancel(); localRequest = UUID(); localTrackKey = ""; lastTrackID = ""; embeddedArtworkKey = ""; localLookupRunning = false; remoteRequest = UUID()
            if changed { revision += 1 }; completion?(); return
        }
        busy = true
        queue.async {
            let (r, error) = Self.script("""
            tell application "Spotify"
                if player state is stopped then return {"", "", "", "", "stopped", 0, 1, ""}
                set coverAddress to ""
                set trackIdentifier to ""
                try
                    set coverAddress to artwork url of current track
                end try
                try
                    set trackIdentifier to id of current track
                end try
                return {name of current track, artist of current track, album of current track, coverAddress, player state as string, player position, duration of current track, trackIdentifier}
            end tell
            """)
            let values = (1...8).map { r?.atIndex($0)?.stringValue ?? "" }
            DispatchQueue.main.async {
                self.busy = false
                if let error { let changed = self.message != error || self.connected; self.message = error; self.scriptingMessage = error; self.connected = false; if changed { self.revision += 1 }; completion?(); return }
                self.applyTrackState(values)
                completion?()
            }
        }
    }
    func applyTrackState(_ values: [String]) {
        guard values.count == 8 else { return }
        let oldKey = "\(title)|\(artist)|\(album)|\(playing)|\(connected)|\(message ?? "")|\(artURL)"
        connected = true
        if message == scriptingMessage { message = nil }; scriptingMessage = nil
        title = values[0].isEmpty ? "Choose something to play" : values[0]
        artist = values[1].isEmpty ? "Your Spotify is connected" : values[1]
        album = values[2]; playing = values[4] == "playing"
        position = Double(values[5]) ?? 0; duration = max(1, (Double(values[6]) ?? 1000) / 1000)
        // Spotify can reuse or briefly omit local IDs while skipping. Metadata identifies artwork.
        let identity = [values[0], values[1], values[2]].map(LocalArtwork.normalized).joined(separator: "|")
        if lastTrackID != identity {
            lastTrackID = identity; remoteRequest = UUID(); artworkTask?.cancel(); artworkTask = nil
            artwork = nil; artURL = ""; embeddedArtworkKey = ""
            localArtworkStatus = "Embedded artwork is read from local audio files."
            localArtworkTask?.cancel(); localRequest = UUID(); localTrackKey = ""; localLookupRunning = false
            localRetryAt = .distantPast; localAttempts = 0
        }
        loadArtwork(values[3])
        loadLocalArtwork(id: values[7], missingCover: values[3].isEmpty, title: values[0], artist: values[1], album: values[2])
        let newKey = "\(title)|\(artist)|\(album)|\(playing)|\(connected)|\(message ?? "")|\(artURL)"
        if oldKey != newKey { revision += 1 }
    }
    private func loadArtwork(_ value: String) {
        guard !usingEmbeddedArtwork else { return }
        guard value != artURL || (artwork == nil && artworkTask == nil) else { return }
        artworkTask?.cancel(); artURL = value; artwork = nil; remoteRequest = UUID()
        guard let url = URL(string: value), url.scheme == "https" else { return }
        let request = remoteRequest, identity = lastTrackID
        artworkTask = URLSession.shared.dataTask(with: url) { data, _, _ in
            DispatchQueue.main.async {
                guard self.remoteRequest == request, self.lastTrackID == identity, !self.usingEmbeddedArtwork else { return }
                self.artworkTask = nil
                if let data, let image = NSImage(data: data) { self.artwork = image; self.revision += 1 }
            }
        }
        artworkTask?.resume()
    }
    private func installEmbedded(_ data: Data, identity: String) -> Bool {
        guard identity == lastTrackID, let image = NSImage(data: data) else { return false }
        embeddedArtworkKey = identity; remoteRequest = UUID(); artworkTask?.cancel(); artworkTask = nil
        artwork = image; localArtworkStatus = "Using the local file’s embedded album cover."
        revision += 1; return true
    }
    private func loadLocalArtwork(id: String, missingCover: Bool, title: String, artist: String, album: String) {
        let key = lastTrackID
        if usingEmbeddedArtwork { return }
        guard id.hasPrefix("spotify:local") || id.hasPrefix("file:") || id.isEmpty || (missingCover && !title.isEmpty && !artist.isEmpty) else { return }
        guard !title.isEmpty else { return }
        if let cached = localCoverCache[key], installEmbedded(cached, identity: key) { return }
        if localTrackKey != key {
            localArtworkTask?.cancel(); localRequest = UUID(); localTrackKey = key; localLookupRunning = false
            localAttempts = 0; localRetryAt = .distantPast
        }
        guard !localLookupRunning, Date() >= localRetryAt else { return }
        localLookupRunning = true; localAttempts += 1
        let request = UUID(); localRequest = request
        localArtworkStatus = "Looking for embedded artwork…"
        let folders = localFolders, finder = findLocalArtwork
        localArtworkTask = Task.detached(priority: .utility) { [weak self] in
            guard let owner = self else { return }
            let data = await finder(title, artist, album, folders)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard owner.localRequest == request, owner.localTrackKey == key, owner.lastTrackID == key else { return }
                owner.localLookupRunning = false
                if let data, owner.installEmbedded(data, identity: key) {
                    if owner.localCoverCache.count >= 40 { owner.localCoverCache.removeAll() }
                    owner.localCoverCache[key] = data
                } else {
                    let delay = min(30.0, 0.5 * pow(2.0, Double(min(owner.localAttempts - 1, 6))))
                    owner.localRetryAt = Date().addingTimeInterval(delay)
                    owner.localArtworkStatus = "Waiting for local artwork; retrying automatically."
                }
            }
        }
    }
    func setBackContrast(_ enabled: Bool) {
        backContrast = enabled; UserDefaults.standard.set(enabled, forKey: "widgetBackContrast"); revision += 1
    }
    func setTintedText(_ enabled: Bool) {
        tintedText = enabled; UserDefaults.standard.set(enabled, forKey: "widgetTintedText"); revision += 1
    }
    func setGrayscale(_ enabled: Bool) {
        grayscale = enabled; UserDefaults.standard.set(enabled, forKey: "widgetGrayscale"); revision += 1
    }
    func setStyle(_ style: String) {
        styleOverride = style; UserDefaults.standard.set(style, forKey: "widgetStyleOverride"); revision += 1
    }
    func addLocalFolders() {
        let picker = NSOpenPanel(); picker.title = "Choose local music folders"; picker.canChooseFiles = false; picker.canChooseDirectories = true; picker.allowsMultipleSelection = true
        guard picker.runModal() == .OK else { return }
        for url in picker.urls where !localFolders.contains(url.path) { localFolders.append(url.path) }
        UserDefaults.standard.set(localFolders, forKey: "localMusicFolders")
        localCoverCache.removeAll(); embeddedArtworkKey = ""; localTrackKey = ""; localLookupRunning = false; localRetryAt = .distantPast; refresh()
    }
    func command(_ value: String, completion: (() -> Void)? = nil) {
        guard !preview else { completion?(); return }
        message = nil
        queue.async {
            let (_, error) = Self.script("tell application \"Spotify\"\n" + value + "\nend tell")
            DispatchQueue.main.async {
                self.message = error; self.scriptingMessage = error
                if error != nil { self.revision += 1; completion?() }
                else { self.refresh(completion: completion) }
            }
        }
    }
    func openSpotify() { NSWorkspace.shared.open(URL(string: "spotify:")!) }
}
