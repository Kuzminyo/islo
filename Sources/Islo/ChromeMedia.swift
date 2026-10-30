import Foundation

/// A Chrome tab that is playing, addressed by its window and tab ids.
struct ChromeTab: Equatable {
    let windowID: Int
    let tabID: Int
}

/// Reads and controls music playing in Google Chrome tabs through AppleScript.
///
/// macOS no longer shares "Now Playing" with third-party apps, so Islo asks Chrome to run a
/// little JavaScript in tabs of music sites. This needs Chrome's
/// View → Developer → Allow JavaScript from Apple Events, switched on once.
enum ChromeMedia {
    static let bundleID = "com.google.Chrome"

    /// Sites worth looking at; other tabs are skipped so polling stays cheap.
    private static let hosts = [
        "youtube.com", "soundcloud.com", "open.spotify.com", "music.yandex", "music.apple.com",
        "deezer.com", "vk.com", "tidal.com", "bandcamp.com", "mixcloud.com",
    ]

    struct Result {
        let tab: ChromeTab
        let title: String
        let artist: String
        let artworkURL: URL?
        let duration: Double
        let position: Double
        let isPlaying: Bool
    }

    enum Failure: Error {
        /// Chrome refuses to run JavaScript sent from AppleScript.
        case javaScriptDisabled
        case other
    }

    // MARK: - Page scripts

    /// Finds the page's media element (a playing one first) and the Media Session metadata.
    private static let readJS = """
    (function(){var ms=[].slice.call(document.querySelectorAll('video,audio')).filter(function(e){return e.duration>0&&isFinite(e.duration)});\
    ms.sort(function(a,b){return a.paused-b.paused});var m=ms[0];var s=navigator.mediaSession;var md=s&&s.metadata;\
    if(!m&&!md)return '';var on=m?!m.paused:(s&&s.playbackState==='playing');var art='';\
    if(md&&md.artwork&&md.artwork.length){art=md.artwork[md.artwork.length-1].src}\
    var d=m?m.duration:0,p=m?m.currentTime:0;\
    if(!m){var tp=document.querySelector('.playbackTimeline__timePassed span[aria-hidden]'),du=document.querySelector('.playbackTimeline__duration span[aria-hidden]');\
    var sec=function(x){return x.textContent.trim().split(':').reduce(function(a,b){return a*60+Number(b)},0)};if(tp&&du){p=sec(tp);d=sec(du)}}\
    return JSON.stringify({t:(md&&md.title)||document.title,a:(md&&md.artist)||'',art:art,d:d,p:p,on:!!on})})()
    """

    /// Clicks the site's own play/next/previous button when it has one, otherwise drives the
    /// media element directly. `seek` sets the position in seconds.
    private static func controlJS(_ action: String, _ value: Double = 0) -> String {
        """
        (function(a,x){var h=location.hostname;var sel=[];\
        if(h.indexOf('music.youtube.com')>=0)sel=['#play-pause-button','.next-button','.previous-button'];\
        else if(h.indexOf('youtube.com')>=0)sel=['.ytp-play-button','.ytp-next-button','.ytp-prev-button'];\
        else if(h.indexOf('soundcloud.com')>=0)sel=['.playControl','.skipControl__next','.skipControl__previous'];\
        else if(h.indexOf('open.spotify.com')>=0)sel=['[data-testid=control-button-playpause]','[data-testid=control-button-skip-forward]','[data-testid=control-button-skip-back]'];\
        else if(h.indexOf('music.yandex')>=0)sel=['.player-controls__btn_play','.player-controls__btn_next','.player-controls__btn_prev'];\
        var m=[].slice.call(document.querySelectorAll('video,audio')).filter(function(e){return e.duration>0})[0];\
        if(a==='seek'){if(m){m.currentTime=x;return 'ok'}\
        var w=document.querySelector('.playbackTimeline__progressWrapper'),du=document.querySelector('.playbackTimeline__duration span[aria-hidden]');\
        if(!w||!du)return 'no';var d=du.textContent.trim().split(':').reduce(function(s,v){return s*60+Number(v)},0);\
        var r=w.getBoundingClientRect(),cx=r.left+r.width*Math.min(Math.max(x/d,0),1),cy=r.top+r.height/2;\
        ['mousedown','mouseup','click'].forEach(function(n){w.dispatchEvent(new MouseEvent(n,{bubbles:true,clientX:cx,clientY:cy}))});return 'ok'}\
        var i={play:0,next:1,prev:2}[a];var b=sel[i]&&document.querySelector(sel[i]);\
        if(b&&b.offsetParent!==null){b.click();return 'ok'}\
        if(!m)return 'no';if(a==='play'){if(m.paused)m.play();else m.pause()}\
        else if(a==='next'){m.currentTime=m.duration}else{m.currentTime=0}return 'ok'})('\(action)',\(value))
        """
    }

    // MARK: - AppleScript

    /// Escapes a page script for an AppleScript string literal.
    private static func quoted(_ js: String) -> String {
        "\"" + js.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static var pollScript: String {
        let hostCheck = hosts.map { "u contains \"\($0)\"" }.joined(separator: " or ")
        // Each Chrome profile has its own "Allow JavaScript from Apple Events" switch, so a tab
        // that refuses is skipped instead of failing the whole poll.
        return """
        tell application "Google Chrome"
            set out to ""
            set refused to ""
            repeat with w in windows
                repeat with t in tabs of w
                    set u to URL of t
                    if \(hostCheck) then
                        try
                            set r to execute t javascript \(quoted(readJS))
                            if r is not missing value and r is not "" then set out to out & (id of w) & "||" & (id of t) & "||" & r & linefeed
                        on error message
                            set refused to message
                        end try
                    end if
                end repeat
            end repeat
            if out is "" and refused is not "" then return "REFUSED||" & refused
            return out
        end tell
        """
    }

    private static func inTab(_ tab: ChromeTab, _ body: String) -> String {
        """
        tell application "Google Chrome"
            repeat with w in windows
                if (id of w) is \(tab.windowID) then
                    set i to 0
                    repeat with t in tabs of w
                        set i to i + 1
                        if (id of t) is \(tab.tabID) then
                            \(body)
                        end if
                    end repeat
                end if
            end repeat
            return ""
        end tell
        """
    }

    /// The playing tab (or the first tab with media) across all Chrome windows.
    static func poll() -> Swift.Result<Result?, Failure> {
        let (output, error) = run(pollScript)
        if let error {
            return .failure(error.contains("JavaScript") ? .javaScriptDisabled : .other)
        }
        if let output, output.hasPrefix("REFUSED||") {
            return .failure(.javaScriptDisabled)
        }
        let results = (output ?? "").split(separator: "\n").compactMap { parse(String($0)) }
        return .success(results.first(where: \.isPlaying) ?? results.first)
    }

    static func control(_ action: String, value: Double = 0, in tab: ChromeTab) {
        run(inTab(tab, "return (execute t javascript \(quoted(controlJS(action, value))))"))
    }

    /// Brings the tab to the front.
    static func reveal(_ tab: ChromeTab) {
        run(inTab(tab, """
        set active tab index of w to i
        set index of w to 1
        activate
        return ""
        """))
    }

    @discardableResult
    private static func run(_ source: String) -> (String?, String?) {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            return (nil, error[NSAppleScript.errorMessage] as? String ?? "error")
        }
        return (result?.stringValue, nil)
    }

    private static func parse(_ line: String) -> Result? {
        let parts = line.components(separatedBy: "||")
        guard parts.count >= 3, let windowID = Int(parts[0]), let tabID = Int(parts[1]),
              let data = parts[2...].joined(separator: "||").data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let title = (json["t"] as? String ?? "")
            .replacingOccurrences(of: " - YouTube Music", with: "")
            .replacingOccurrences(of: " - YouTube", with: "")
        return Result(
            tab: ChromeTab(windowID: windowID, tabID: tabID),
            title: title,
            artist: json["a"] as? String ?? "",
            artworkURL: (json["art"] as? String).flatMap(URL.init(string:)),
            duration: json["d"] as? Double ?? 0,
            position: json["p"] as? Double ?? 0,
            isPlaying: json["on"] as? Bool ?? false
        )
    }
}
