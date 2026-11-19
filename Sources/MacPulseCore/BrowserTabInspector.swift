import Foundation

public enum BrowserTabInspector {
    public static func normalizeURL(_ raw: String) -> String {
        guard var comp = URLComponents(string: raw) else { return raw }
        comp.fragment = nil
        var s = comp.string ?? raw
        if s.hasSuffix("/") && (comp.path.count > 1) && comp.query == nil {
            s.removeLast()
        }
        return s
    }

    public static func findDuplicates(in tabs: [BrowserTabItem]) -> [DuplicateTabGroup] {
        var grouped: [String: [BrowserTabItem]] = [:]
        for t in tabs where !t.url.isEmpty && t.url != "about:blank" {
            let norm = normalizeURL(t.url)
            grouped[norm, default: []].append(t)
        }
        return grouped
            .filter { $0.value.count >= 2 }
            .map { DuplicateTabGroup(normalizedURL: $0.key, tabs: $0.value) }
            .sorted { $0.tabs.count > $1.tabs.count }
    }

    public static func fetchRunningBrowserTabs() -> (tabs: [BrowserTabItem], warnings: [String]) {
        var allTabs: [BrowserTabItem] = []
        var warnings: [String] = []

        for appName in ["Google Chrome", "Microsoft Edge"] {
            let script = """
            if application "\(appName)" is running then
                tell application "\(appName)"
                    set outText to ""
                    set wIdx to 1
                    repeat with w in windows
                        set tIdx to 1
                        repeat with t in tabs of w
                            set outText to outText & wIdx & "\t" & tIdx & "\t" & (URL of t) & "\t" & (title of t) & linefeed
                            set tIdx to tIdx + 1
                        end repeat
                        set wIdx to wIdx + 1
                    end repeat
                    return outText
                end tell
            else
                return ""
            end if
            """
            var errorInfo: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                let desc = appleScript.executeAndReturnError(&errorInfo)
                if let err = errorInfo {
                    let msg = (err[NSAppleScript.errorMessage] as? String) ?? "Chưa cấp quyền Automation"
                    warnings.append("\(appName): \(msg)")
                } else {
                    let raw = desc.stringValue ?? ""
                    for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
                        let parts = line.split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
                        if parts.count == 4, let w = Int(parts[0]), let t = Int(parts[1]) {
                            allTabs.append(BrowserTabItem(browser: appName, windowIndex: w, tabIndex: t, title: parts[3], url: parts[2]))
                        }
                    }
                }
            }
        }
        return (allTabs, warnings)
    }

    public static func closeTab(_ tab: BrowserTabItem) -> Bool {
        let escapedURL = tab.url.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "\(tab.browser)"
            if (count of windows) >= \(tab.windowIndex) then
                tell window \(tab.windowIndex)
                    if (count of tabs) >= \(tab.tabIndex) then
                        if URL of tab \(tab.tabIndex) is "\(escapedURL)" then
                            close tab \(tab.tabIndex)
                            return "closed"
                        end if
                    end if
                end tell
            end if
        end tell
        return "mismatch"
        """
        var err: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else { return false }
        let desc = appleScript.executeAndReturnError(&err)
        return err == nil && desc.stringValue == "closed"
    }
}
