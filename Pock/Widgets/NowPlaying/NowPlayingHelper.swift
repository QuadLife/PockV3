//
//  NowPlayingHelper.swift
//  Pock
//
//  Created by Pierluigi Galdi on 17/02/2019.
//  Copyright © 2019 Pierluigi Galdi. All rights reserved.
//

import Foundation
import Defaults

/**
 Reads Now Playing information (title, artist, album, artwork, playback state)
 directly from Apple Music and Spotify through AppleScript.

 The private MediaRemote framework used previously is gated by Apple on recent
 macOS versions and no longer returns any information to third-party apps.
*/
class NowPlayingHelper {

    /// Core
    public static let shared: NowPlayingHelper = NowPlayingHelper()
    public static let kNowPlayingItemDidChange: Notification.Name = Notification.Name(rawValue: "kNowPlayingItemDidChange")

    /// Data
    public var nowPlayingItem: NowPlayingItem = NowPlayingItem()

    /// Polling
    private var pollTimer: Timer?
    private let pollInterval: TimeInterval = 2.0
    private let pollQueue = DispatchQueue(label: "Pock.NowPlayingPoll", qos: .utility)

    /// AppleScript sources, one per supported player app
    private static let musicQueryScript   = NowPlayingHelper.stateAndTrackScript(forApp: "Music")
    private static let spotifyQueryScript = NowPlayingHelper.stateAndTrackScript(forApp: "Spotify")

    /// Artwork
    private var lastArtworkKey: String?
    private var pendingArtworkSearchKey: String?
    var cachedAlbumArtName: String? = nil
    var cachedAlbumArt: Data? = nil

    private init() {
        startPolling()
    }

    deinit {
        pollTimer?.invalidate()
    }

    ///  Starts the polling timer on the main thread; the actual AppleScript work happens on `pollQueue`.
    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true, block: { [weak self] _ in
            self?.poll()
        })
        poll()
    }

    ///  AppleScript returning "state|title|artist|album" for the given player app.
    private static func stateAndTrackScript(forApp app: String) -> String {
        return """
        tell application "\(app)"
        \tset out to (player state as text)
        \ttry
        \t\tset out to out & "|" & name of current track & "|" & artist of current track & "|" & album of current track
        \ton error
        \t\tset out to out & "|||"
        \tend try
        end tell
        return out
        """
    }

    ///  Runs an AppleScript with `/usr/bin/osascript` and returns its string output.
    private func runScript(_ source: String) -> String? {
        guard let scriptData = source.data(using: .utf8) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        do {
            try process.run()
        } catch {
            return nil
        }
        // Feed the script through the standard input pipe.
        stdinPipe.fileHandleForWriting.write(scriptData)
        stdinPipe.fileHandleForWriting.closeFile()
        let handle = stdoutPipe.fileHandleForReading
        defer { handle.closeFile() }
        let data = handle.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    ///  Whether an app with the given bundle identifier is currently running.
    private func isAppRunning(_ bundleIdentifier: String) -> Bool {
        return NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == bundleIdentifier && !$0.isTerminated
        }
    }

    ///  Schedules one poll cycle on the background queue.
    private func poll() {
        pollQueue.async { [weak self] in
            guard let self = self else { return }

            let musicBundleID   = "com.apple.Music"
            let spotifyBundleID = "com.spotify.client"

            // Read the state and track info of both player apps, without launching them.
            var sourceBundleID: String? = nil
            var isPlaying: Bool         = false
            var title: String?          = nil
            var artist: String?         = nil
            var album: String?          = nil

            let musicState   = self.isAppRunning(musicBundleID)   ? self.readStateAndTrack(Self.musicQueryScript)   : nil
            let spotifyState = self.isAppRunning(spotifyBundleID) ? self.readStateAndTrack(Self.spotifyQueryScript) : nil

            // Prefer the app that is actually playing, otherwise keep the last used app's paused track.
            if musicState?.isPlaying == true {
                sourceBundleID = musicBundleID
                isPlaying      = true
                title          = musicState?.title
                artist         = musicState?.artist
                album          = musicState?.album
            } else if spotifyState?.isPlaying == true {
                sourceBundleID = spotifyBundleID
                isPlaying      = true
                title          = spotifyState?.title
                artist         = spotifyState?.artist
                album          = spotifyState?.album
            } else if let music = musicState, music.hasTrack {
                sourceBundleID = musicBundleID
                title          = music.title
                artist         = music.artist
                album          = music.album
            } else if let spotify = spotifyState, spotify.hasTrack {
                sourceBundleID = spotifyBundleID
                title          = spotify.title
                artist         = spotify.artist
                album          = spotify.album
            }

            DispatchQueue.main.async {
                self.applyPollResult(sourceBundleID: sourceBundleID, isPlaying: isPlaying,
                                     title: title, artist: artist, album: album)
            }
        }
    }

    ///  Result of the state/track AppleScript.
    private struct PlayerState {
        var state: String
        var title: String?
        var artist: String?
        var album: String?

        var isPlaying: Bool { return state == "playing" }
        var hasTrack: Bool  { return title != nil && !title!.isEmpty }
    }

    ///  Reads "state|title|artist|album" from the given AppleScript source.
    private func readStateAndTrack(_ scriptSource: String) -> PlayerState? {
        guard let result = runScript(scriptSource) else { return nil }
        let parts = result.components(separatedBy: "|")
        guard parts.count >= 4 else { return nil }
        return PlayerState(
            state: parts[0],
            title: parts[1].isEmpty ? nil : parts[1],
            artist: parts[2].isEmpty ? nil : parts[2],
            album: parts[3].isEmpty ? nil : parts[3]
        )
    }

    ///  Updates `nowPlayingItem` from the last poll result (main thread only).
    private func applyPollResult(sourceBundleID: String?, isPlaying: Bool,
                                 title: String?, artist: String?, album: String?) {
        // Nothing is playing at all: reset the item, so the widget shows its idle state.
        guard sourceBundleID != nil else {
            if nowPlayingItem.appBundleIdentifier != nil {
                nowPlayingItem = NowPlayingItem()
                NotificationCenter.default.post(name: NowPlayingHelper.kNowPlayingItemDidChange, object: nil)
            }
            return
        }

        let musicBundleID = "com.apple.Music"
        let spotifyBundleID = "com.spotify.client"

        // Only refresh the UI when something actually changed.
        let artworkEnabled = Defaults[.showArtwork]
        let artworkKey     = "\(title ?? "")|\(artist ?? "")"
        let artworkChanged = lastArtworkKey != artworkKey

        if title == nowPlayingItem.title &&
           artist == nowPlayingItem.artist &&
           album == nowPlayingItem.album &&
           isPlaying == nowPlayingItem.isPlaying &&
           sourceBundleID == nowPlayingItem.appBundleIdentifier &&
           !artworkChanged {
            return
        }

        let artworkData: Data?
        if !artworkChanged {
            artworkData = nowPlayingItem.image
        } else if artworkEnabled, sourceBundleID == musicBundleID, title != nil {
            // The artwork is loaded in the background and posted separately.
            artworkData = nil
            fetchMusicArtwork(forKey: artworkKey)
        } else if artworkEnabled, sourceBundleID == spotifyBundleID {
            // Spotify does not expose its artwork through AppleScript.
            artworkData = cachedArtwork(forKey: artworkKey)
            if artworkData == nil {
                searchArtworkOnline(forKey: artworkKey, withTitle: title ?? "", andArtist: artist ?? "")
            }
        } else {
            artworkData = nil
        }
        lastArtworkKey = artworkKey

        let item = NowPlayingItem()
        item.appBundleIdentifier = sourceBundleID
        item.isPlaying           = isPlaying
        item.title               = title
        item.artist              = artist
        item.album               = album
        item.image               = artworkData

        nowPlayingItem = item
        NotificationCenter.default.post(name: NowPlayingHelper.kNowPlayingItemDidChange, object: nil)
    }

    ///  Exports the current track's artwork from Apple Music in the background
    ///  and posts it once available (main thread only).
    private func fetchMusicArtwork(forKey key: String) {
        let path = Self.artworkFilePath()
        try? FileManager.default.removeItem(atPath: path)
        let scriptSource = Self.artworkScript(forPath: path)
        pollQueue.async { [weak self] in
            _ = self?.runScript(scriptSource)
            let data = FileManager.default.contents(atPath: path)
            try? FileManager.default.removeItem(atPath: path)
            DispatchQueue.main.async {
                guard let self = self, self.lastArtworkKey == key, let data = data else { return }
                self.nowPlayingItem.image = data
                NotificationCenter.default.post(name: NowPlayingHelper.kNowPlayingItemDidChange, object: nil)
            }
        }
    }

    ///  AppleScript exporting the current track's artwork to the given file.
    private static func artworkScript(forPath path: String) -> String {
        return """
        tell application "Music"
        \tif exists artwork 1 of current track then
        \t\tset d to data of artwork 1 of current track
        \t\tset outfile to POSIX file "\(path)"
        \t\tset fid to open for access outfile with write permission
        \t\tset eof of fid to 0
        \t\twrite d to fid
        \t\tclose access fid
        \tend if
        end tell
        """
    }

    private static func artworkFilePath() -> String {
        let name = "PockNowPlayingArtwork-\(getpid())"
        return (NSTemporaryDirectory() as NSString).appendingPathComponent(name)
    }

    ///  Returns a previously fetched artwork from the iTunes Search API cache.
    private func cachedArtwork(forKey key: String) -> Data? {
        guard let name = cachedAlbumArtName else { return nil }
        return name == key ? cachedAlbumArt : nil
    }

    ///  Fetches the artwork for the given track from the iTunes Search API.
    ///  credit: https://github.com/musa11971/Music-Bar
    private func searchArtworkOnline(forKey key: String, withTitle title: String, andArtist artist: String) {
        guard pendingArtworkSearchKey != key else { return }
        pendingArtworkSearchKey = key
        let search = "\(title) \(artist)".replacingOccurrences(of: " ", with: "+").addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? ""
        guard search.count > 0, let url = URL(string: "https://itunes.apple.com/search?term=\(search)&entity=song&limit=1") else { return }
        _ = URLSession.fetchJSON(fromURL: url) { [weak self] (data, json, error) in
            guard error == nil,
                  let json = json as? [String: Any],
                  let results = json["results"] as? [[String: Any]],
                  results.count >= 1,
                  let imgURL = results[0]["artworkUrl100"] as? String,
                  let url = URL(string: imgURL) else {
                return
            }
            URLSession.shared.dataTask(with: url, completionHandler: { (data, response, error) in
                guard error == nil, let data = data else { return }
                DispatchQueue.main.async {
                    self?.cachedAlbumArtName = key
                    self?.cachedAlbumArt     = data
                    if self?.lastArtworkKey == key {
                        self?.nowPlayingItem.image = data
                        NotificationCenter.default.post(name: NowPlayingHelper.kNowPlayingItemDidChange, object: nil)
                    }
                }
            }).resume()
        }
    }

    ///  The name of the player app the widget is currently showing.
    private func targetAppName() -> String {
        switch nowPlayingItem.appBundleIdentifier {
        case "com.spotify.client": return "Spotify"
        default:                   return "Music"
        }
    }

    ///  Runs a quick AppleScript command on the current player app.
    private func runOnPlayerApp(_ command: String) {
        let source = "tell application \"\(targetAppName())\" to \(command)"
        pollQueue.async { [weak self] in
            _ = self?.runScript(source)
        }
    }

}

extension NowPlayingHelper {

    public func togglePlayingState() {
        runOnPlayerApp("playpause")
    }

    public func skipToNextTrack() {
        runOnPlayerApp("next track")
    }

    public func skipToPreviousTrack() {
        runOnPlayerApp("previous track")
    }

}

extension URLSession {
      static func fetchJSON(fromURL url: URL, completionHandler: @escaping (Data?, Any?, Error?) -> Void) -> URLSessionTask {
          let task = URLSession.shared.dataTask(with: url) { (data, response, error) in
              // Error occurred during request
              if error != nil {
                  completionHandler(nil, nil, error)
                  return
              }

            if data == nil {
                completionHandler(nil, nil, NSError(domain:"", code:401, userInfo:[ NSLocalizedDescriptionKey: "Invalid data"]))
                return
            }

            let json = try? JSONSerialization.jsonObject(with: data!, options: .allowFragments)

            if json == nil {
                completionHandler(nil, nil, NSError(domain:"", code:401, userInfo:[ NSLocalizedDescriptionKey: "Invalid json"]))
                return
            }

            completionHandler(data, json, nil)
          }

          return task
      }
  }