import Foundation
import MacPulseCore

let suite = TestSuite()

suite.test("Formatters.bytes formats MB and GB consistently") {
    try expectEqual(Formatters.bytes(1_048_576), "1.0 MB")
    try expectEqual(Formatters.bytes(2_147_483_648), "2.00 GB")
}

suite.test("MemoryMetrics calculates pressure ratio correctly") {
    let mem = MemoryMetrics(
        totalBytes: 16 * 1_073_741_824,
        activeBytes: 5 * 1_073_741_824,
        inactiveBytes: 4 * 1_073_741_824,
        wiredBytes: 2 * 1_073_741_824,
        compressedBytes: 5 * 1_073_741_824,
        freeBytes: 512 * 1_048_576,
        purgeableBytes: 100 * 1_048_576,
        swapTotalBytes: 0,
        swapUsedBytes: 0,
        swapins: 0,
        swapouts: 0
    )
    try expect(mem.compressedGB > 4.9 && mem.compressedGB < 5.1, "compressedGB should be ~5.0")
    try expectEqual(mem.isCompressorHeavy, true, "5 GB compressed should flag heavy")
}

suite.test("SystemTelemetry reads real M2 memory, CPU, and disk metrics within bounds") {
    let reader = SystemTelemetryReader()
    let s1 = try reader.captureSnapshot()
    try expect(s1.memory.totalBytes >= 8 * 1_073_741_824, "RAM >= 8 GB")
    try expect(s1.cpu.coreCount >= 4, "coreCount >= 4")
    try expect(s1.disk.totalBytes > 50 * 1_073_741_824, "disk > 50 GB")
    Thread.sleep(forTimeInterval: 0.15)
    let s2 = try reader.captureSnapshot()
    let totalCPU = s2.cpu.userPercent + s2.cpu.systemPercent + s2.cpu.idlePercent
    try expect(totalCPU > 98.0 && totalCPU < 102.0, "CPU percentages sum to ~100%, got \(totalCPU)")
}

suite.test("ProcessScanner groups Chrome helpers and flags orphaned Puppeteer Chrome separately") {
    let samplePS = """
      PID  PPID  %CPU     RSS ELAPSED COMM ARGS
    10772     1   0.8  460416 01:02:00 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome /Applications/Google Chrome.app/Contents/MacOS/Google Chrome
    10778 10772   5.7  127888 01:01:58 /Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Helper /Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Helper --type=gpu-process
    11584 11580  18.5  450000 00:15:00 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome /Applications/Google Chrome.app/Contents/MacOS/Google Chrome --enable-automation --user-data-dir=/var/folders/xx/puppeteer_dev_chrome_profile-abc123 about:blank
    14145     1  91.7   35232 00:14:34 /usr/libexec/replayd /usr/libexec/replayd
     5852     1  20.6  207936 /Applications/ChatGPT.app/Contents/MacOS/ChatGPT /Applications/ChatGPT.app/Contents/MacOS/ChatGPT
     6296  5852  20.0   30720 /Users/ducdung/.codex/computer-use/Codex Computer Use.app/Contents/MacOS/SkyComputerUseService /Users/ducdung/.codex/computer-use/Codex Computer Use.app/Contents/MacOS/SkyComputerUseService
    """
    let parsed = ProcessScanner.parsePSOutput(samplePS)
    try expectEqual(parsed.count, 6, "Should parse all 6 rows")

    let groups = ProcessScanner.aggregate(parsed)
    let orphan = groups.first { $0.isOrphanAutomation }
    try expect(orphan != nil, "Should detect orphan Puppeteer Chrome")
    try expectEqual(orphan?.pids ?? [], [11584], "Orphan PID should be 11584")
    try expectEqual(orphan?.actionKind, .killOrphanPuppeteer, "Orphan action should be killOrphanPuppeteer")

    let mainChrome = groups.first { $0.id == "app:Google Chrome" }
    try expectEqual(mainChrome?.processCount, 2, "Main Chrome should group 10772 + 10778")
}

suite.test("HealthAnalyzer flags replayd XPC storm and compressor pressure") {
    let snap = SystemSnapshot(
        cpu: CPUMetrics(userPercent: 35, systemPercent: 30, idlePercent: 35, coreCount: 8, load1m: 4.2, load5m: 3.9, load15m: 3.5),
        memory: MemoryMetrics(
            totalBytes: 16 * 1_073_741_824,
            activeBytes: 5 * 1_073_741_824,
            inactiveBytes: 4 * 1_073_741_824,
            wiredBytes: 2 * 1_073_741_824,
            compressedBytes: 6 * 1_073_741_824,
            freeBytes: 128 * 1_048_576,
            purgeableBytes: 0,
            swapTotalBytes: 2 * 1_073_741_824,
            swapUsedBytes: 1 * 1_073_741_824,
            swapins: 10,
            swapouts: 25
        ),
        disk: DiskMetrics(totalBytes: 228 * 1_073_741_824, availableBytes: 22 * 1_073_741_824, usedBytes: 206 * 1_073_741_824)
    )
    let groups = [
        ProcessGroupSummary(id: "sys:replayd", displayName: "replayd (macOS ScreenCapture daemon)", processCount: 1, totalCPUPercent: 95.0, totalRSSBytes: 35_000_000, pids: [14145]),
        ProcessGroupSummary(id: "orphan:puppeteer-chrome", displayName: "Chrome Automation ngầm (Puppeteer)", processCount: 3, totalCPUPercent: 20.0, totalRSSBytes: 470_000_000, pids: [11584], isOrphanAutomation: true, actionKind: .killOrphanPuppeteer)
    ]

    let report = HealthAnalyzer.analyze(snapshot: snap, processGroups: groups)
    try expect(report.score < 60, "Score should drop below 60 under combined load")
    try expectEqual(report.severity, .critical, "Severity should be critical")
    try expect(report.findings.contains { $0.id == "replayd-storm" }, "Should detect replayd storm")
    try expect(report.findings.contains { $0.id == "orphan-puppeteer" }, "Should detect orphan puppeteer")
    try expect(report.findings.contains { $0.id == "memory-compressor" }, "Should detect compressor")
}

suite.test("BenchmarkRunner executes real CPU, RAM, and 16MB SSD tests and cleans temp file") {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("macpulse-bench-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let runner = BenchmarkRunner(historyFileURL: tempDir.appendingPathComponent("history.json"), diskTestBytes: 16 * 1_048_576)
    let result = try runner.runSync(localURLToProbe: nil)
    try expect(result.cpuSingleOpsPerSec > 0, "Single CPU > 0")
    try expect(result.cpuMultiOpsPerSec >= result.cpuSingleOpsPerSec, "Multi CPU >= Single CPU")
    try expect(result.memoryBandwidthGBs > 1.0, "M2 memory bandwidth > 1 GB/s")
    try expect(result.diskWriteMBs > 50.0, "M2 SSD write > 50 MB/s")
    try expect(result.diskReadMBs > 50.0, "M2 SSD read > 50 MB/s")
    try expect(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("history.json").path), "History JSON saved")

    let loaded = runner.loadHistory()
    try expectEqual(loaded.count, 1, "Should load 1 saved benchmark")
}

suite.test("CleanupScanner and CleanupExecutor clean Tier-1 caches without touching Tier-2 DBs") {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("macpulse-clean-test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }

    let cacheDir = root.appendingPathComponent("Library/Caches/Google/Chrome/Default/Cache")
    let opencodeDir = root.appendingPathComponent(".local/share/opencode")
    let chambeshiLogDir = root.appendingPathComponent("Local Sites/chambeshi/logs/php")
    try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: opencodeDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: chambeshiLogDir, withIntermediateDirectories: true)

    let dummyCache = Data(repeating: 0x41, count: 512_000)
    try dummyCache.write(to: cacheDir.appendingPathComponent("data_0"))

    let dummyDB = Data(repeating: 0x42, count: 2_000_000)
    let dbURL = opencodeDir.appendingPathComponent("opencode.db")
    try dummyDB.write(to: dbURL)

    let bigLogURL = chambeshiLogDir.appendingPathComponent("error.log")
    try Data(repeating: 0x43, count: 1_200_000).write(to: bigLogURL)

    let scanner = CleanupScanner(homeDirectory: root, oversizedLogThresholdBytes: 1_000_000, inspectThresholdBytes: 1_000_000)
    let items = scanner.scan()

    let tier1Cache = items.first { $0.id == "cache-chrome" }
    try expect(tier1Cache != nil && (tier1Cache?.sizeBytes ?? 0) >= 512_000, "Chrome cache detected")
    try expectEqual(tier1Cache?.tier, .safeAutoClean, "Chrome cache must be Tier 1")

    let tier2DB = items.first { $0.id == "inspect-opencode-db" }
    try expect(tier2DB != nil, "opencode.db detected")
    try expectEqual(tier2DB?.tier, .inspectOnly, "opencode.db must be Tier 2 inspectOnly")

    let outcome = CleanupExecutor.execute(candidates: items, homeDirectory: root)
    try expect(outcome.freedBytes >= 1_700_000, "Should free cache + truncated log")
    try expect(FileManager.default.fileExists(atPath: dbURL.path), "Tier 2 opencode.db MUST remain untouched")
    try expectEqual(CleanupScanner.directorySize(at: cacheDir), 0, "Cache dir contents cleared")
}

suite.test("BrowserTabInspector normalizes and groups duplicate tabs") {
    let tabs = [
        BrowserTabItem(browser: "Google Chrome", windowIndex: 1, tabIndex: 1, title: "Edit Page Saltoro", url: "http://alonepro.local/wp-admin/post.php?post=22753&action=edit"),
        BrowserTabItem(browser: "Google Chrome", windowIndex: 1, tabIndex: 2, title: "Edit Page Saltoro", url: "http://alonepro.local/wp-admin/post.php?post=22753&action=edit#top"),
        BrowserTabItem(browser: "Google Chrome", windowIndex: 1, tabIndex: 3, title: "Saltoro", url: "http://alonepro.local/saltoro/"),
        BrowserTabItem(browser: "Microsoft Edge", windowIndex: 1, tabIndex: 1, title: "Saltoro", url: "http://alonepro.local/saltoro")
    ]
    let dupes = BrowserTabInspector.findDuplicates(in: tabs)
    try expectEqual(dupes.count, 2, "Should find 2 duplicate URL groups")
    try expectEqual(dupes[0].tabs.count, 2, "Each group has 2 tabs")
}


suite.test("IME 01: Telex basic tones sắc/huyền/hỏi/ngã/nặng") {
    let eng = VietnameseEngine(settings: VietnameseSettings(inputMethod: .telex))
    try expectEqual(eng.simulate("as af ar ax aj "), "á à ả ã ạ ")
    try expectEqual(eng.simulate("mas maf mar max maj "), "má mà mả mã mạ ")
}

suite.test("IME 02: Telex circumflex â, ê, ô and breve ă and đ") {
    let eng = VietnameseEngine(settings: VietnameseSettings(inputMethod: .telex))
    try expectEqual(eng.simulate("aa ee oo aw ddi "), "â ê ô ă đi ")
    try expectEqual(eng.simulate("caanf tieengs boonj nawnf ddawngj "), "cần tiếng bộn nằn đặng ")
}

suite.test("IME 03: Telex horn ơ, ư and compound uo->ươ in all typing orders") {
    let eng = VietnameseEngine(settings: VietnameseSettings(inputMethod: .telex))
    try expectEqual(eng.simulate("mow muw thuwowcs thuowcs thuwocs thuocws "), "mơ mư thước thước thước thước ")
    try expectEqual(eng.simulate("nguwowif nguowif dduwowcj dduocwj "), "người người được được ")
}

suite.test("IME 04: Telex open uơ (thuở, huơ) vs closed ươ (lược, rượu, tươi)") {
    let eng = VietnameseEngine(settings: VietnameseSettings(inputMethod: .telex))
    try expectEqual(eng.simulate("thuowr huow ruowuj tuwowis tuoiws "), "thuở huơ rượu tưới tưới ")
}

suite.test("IME 05: Telex gi onset (gì vs giá vs giếng vs giường)") {
    let eng = VietnameseEngine(settings: VietnameseSettings(inputMethod: .telex))
    try expectEqual(eng.simulate("gif gias gieesng giuwowngf "), "gì giá giếng giường ")
}

suite.test("IME 06: Telex qu onset (quá, quý, quốc, quỳnh, quặn)") {
    let eng = VietnameseEngine(settings: VietnameseSettings(inputMethod: .telex))
    try expectEqual(eng.simulate("quas quys quoocs quynhf quawnj "), "quá quý quốc quỳnh quặn ")
}

suite.test("IME 07: Telex oa/oă/oe/uă/ưa/ưi/ưu priority rules") {
    let eng = VietnameseEngine(settings: VietnameseSettings(inputMethod: .telex))
    try expectEqual(eng.simulate("hoawcj xoawns cuawr luawj guwir luuw cuuws "), "hoặc xoắn cửa lựa gửi lưu cứu ")
}

suite.test("IME 08: Telex 3-vowel triphthongs (tuyết, nguyễn, khuỷa, khuỷu, hiểu, yêu)") {
    let eng = VietnameseEngine(settings: VietnameseSettings(inputMethod: .telex))
    try expectEqual(eng.simulate("tuyeets nguyeenx khuyar khuyur hieeur yeeu "), "tuyết nguyễn khuỷa khuỷu hiểu yêu ")
}

suite.test("IME 09: Telex ngh/nh/kh/ph/th/tr/ch multi-char onsets and codas") {
    let eng = VietnameseEngine(settings: VietnameseSettings(inputMethod: .telex))
    try expectEqual(eng.simulate("nghieengf nhaan khuyeenf phuwowngf thoois truwowfng chieefu "), "nghiềng nhân khuyền phường thối trường chiều ")
}

suite.test("IME 10: Telex uppercase and Title Case preservation") {
    let eng = VietnameseEngine(settings: VietnameseSettings(inputMethod: .telex))
    try expectEqual(eng.simulate("Vieejt Nam DDuwowfng "), "Việt Nam Đường ")
    try expectEqual(eng.simulate("VIEEJTT NAM DDUWOWFNG "), "VIEEJTT NAM ĐƯỜNG ")
}

suite.test("IME 11: Modern orthography (hoà, thuý, uỷ, hoè)") {
    let eng = VietnameseEngine(settings: VietnameseSettings(inputMethod: .telex, modernOrthography: true))
    try expectEqual(eng.simulate("hoaf thuys uyr hoef toans "), "hoà thuý uỷ hoè toán ")
}

suite.test("IME 12: Classic orthography (hòa, thúy, ủy, hòe)") {
    let eng = VietnameseEngine(settings: VietnameseSettings(inputMethod: .telex, modernOrthography: false))
    try expectEqual(eng.simulate("hoaf thuys uyr hoef toans "), "hòa thúy ủy hòe toán ")
}

suite.test("IME 13: VNI tones 1-5 and clear 0") {
    let eng = VietnameseEngine(settings: VietnameseSettings(inputMethod: .vni))
    try expectEqual(eng.simulate("ma1 ma2 ma3 ma4 ma5 ma10 "), "má mà mả mã mạ ma ")
}

suite.test("IME 14: VNI shapes 6/7/8/9 and compound ươ") {
    let eng = VietnameseEngine(settings: VietnameseSettings(inputMethod: .vni))
    try expectEqual(eng.simulate("a6 e6 o6 o7 u7 a8 d9 Tie6ng1 Vie6t5 d9u7o7c5 "), "â ê ô ơ ư ă đ Tiếng Việt được ")
}

suite.test("IME 15: Telex+VNI hybrid accepts both styles seamlessly") {
    let eng = VietnameseEngine(settings: VietnameseSettings(inputMethod: .telexAndVni))
    try expectEqual(eng.simulate("Tieesng Vie6t5 d9uowcj "), "Tiếng Việt được ")
}

suite.test("IME 16: Telex z clears active tone and falls back to literal z when none") {
    let eng = VietnameseEngine(settings: VietnameseSettings(inputMethod: .telex))
    try expectEqual(eng.simulate("tooisz "), "tôi ")
    try expectEqual(eng.simulate("az "), "az ")
}

suite.test("IME 17: Double-key undo for tones (tois -> toiss, ma -> mass)") {
    let eng = VietnameseEngine(settings: VietnameseSettings(inputMethod: .telex))
    try expectEqual(eng.simulate("toiss "), "tois ")
    try expectEqual(eng.simulate("TOSS "), "TOS ")
}

suite.test("IME 18: Double-key undo for shapes (dd->đ->dd, aa->â->aa, oo->ô->oo, ow->ơ->ow)") {
    let eng = VietnameseEngine(settings: VietnameseSettings(inputMethod: .telex))
    try expectEqual(eng.simulate("dddi toooi caaa moww "), "ddi tooi caa mow ")
}

suite.test("IME 19: Escape key restores exact raw ASCII keystrokes") {
    let eng = VietnameseEngine(settings: VietnameseSettings(inputMethod: .telex))
    try expectEqual(eng.simulate("tieesng\u{1B} "), "tieesng ")
    try expectEqual(eng.simulate("dduwowcj\u{1B} "), "dduwowcj ")
}

suite.test("IME 20: Backspace edits syllable cleanly without phantom tone jumps") {
    let eng = VietnameseEngine(settings: VietnameseSettings(inputMethod: .telex))
    try expectEqual(eng.simulate("vieej\u{08}t "), "vit ")
    try expectEqual(eng.simulate("toans\u{08} "), "toá ")
}

suite.test("IME 21: Spellcheck protects w/z/f/j initial English words") {
    let eng = VietnameseEngine(settings: VietnameseSettings(inputMethod: .telexAndVni, standaloneWAsU: false))
    try expectEqual(eng.simulate("word windows wordPress zoom zero fix firefox just json "), "word windows wordPress zoom zero fix firefox just json ")
}

suite.test("IME 22: Spellcheck protects English consonant clusters (br/cl/pr/st/sw/scr/str)") {
    let eng = VietnameseEngine(settings: VietnameseSettings(inputMethod: .telexAndVni))
    try expectEqual(eng.simulate("browser client print start stop swift script string thread "), "browser client print start stop swift script string thread ")
}

suite.test("IME 23: Spellcheck auto-restores English words with invalid codas or vowel-after-coda") {
    let eng = VietnameseEngine(settings: VietnameseSettings(inputMethod: .telexAndVni))
    try expectEqual(eng.simulate("google local config server error array coffee different password "), "google local config server error array coffee different password ")
}

suite.test("IME 24: Spellcheck auto-restores English words on stop-coda without tone at Space") {
    let eng = VietnameseEngine(settings: VietnameseSettings(inputMethod: .telexAndVni))
    try expectEqual(eng.simulate("root boot loop deep keep meet "), "root boot loop deep keep meet ")
}

suite.test("IME 25: Spellcheck protects common developer keywords, URLs, emails, and CLI commands") {
    let eng = VietnameseEngine(settings: VietnameseSettings(inputMethod: .telexAndVni))
    try expectEqual(eng.simulate("ssh npm css php html macOS iPhone localhost sudo brew text port sort "), "ssh npm css php html macOS iPhone localhost sudo brew text port sort ")
    try expectEqual(eng.simulate("https://devpixel.vn/wp-admin "), "https://devpixel.vn/wp-admin ")
    try expectEqual(eng.simulate("user@gmail.com "), "user@gmail.com ")
}

suite.test("IME 26: Mixed Vietnamese + English developer sentence") {
    let eng = VietnameseEngine(settings: VietnameseSettings(inputMethod: .telexAndVni))
    try expectEqual(
        eng.simulate("Tooi ddang code Swift treen macOS vaf build GitHub "),
        "Tôi đang code Swift trên macOS và build GitHub "
    )
}

suite.test("IME 27: Delayed d->đ works in Vietnamese and stays disabled in dead/android/send") {
    let eng = VietnameseEngine(settings: VietnameseSettings(inputMethod: .telex))
    try expectEqual(eng.simulate("duowngdf dangd dead android send "), "đường đang dead android send ")
}

suite.test("IME 28: Standalone W as Ư toggle when enabled") {
    let engOn = VietnameseEngine(settings: VietnameseSettings(inputMethod: .telex, standaloneWAsU: true))
    try expectEqual(engOn.simulate("w W ww "), "ư Ư w ")
    let engOff = VietnameseEngine(settings: VietnameseSettings(inputMethod: .telex, standaloneWAsU: false))
    try expectEqual(engOff.simulate("w W "), "w W ")
}

suite.test("IME 29: FreeMark disabled restricts tone placement until after vowel") {
    let engStrict = VietnameseEngine(settings: VietnameseSettings(inputMethod: .telex, freeMark: false))
    try expectEqual(engStrict.simulate("toans toasn "), "toans toán ")
}

suite.test("IME 30: Disabled engine or spellCheckOff behaves predictably") {
    let engDisabled = VietnameseEngine(settings: VietnameseSettings(isEnabled: false))
    try expectEqual(engDisabled.simulate("Tieesng Vieejt "), "Tieesng Vieejt ")
    let engNoSpell = VietnameseEngine(settings: VietnameseSettings(inputMethod: .telex, spellCheckEnabled: false))
    try expectEqual(engNoSpell.simulate("worf "), "wò ")
}


suite.test("VietnameseSettingsStore persists settings and per-app map") {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: tmpDir) }
    let fileURL = tmpDir.appendingPathComponent("ime-settings.json")
    let store = VietnameseSettingsStore(fileURL: fileURL)

    var cfg = PersistedVietnameseConfig()
    cfg.settings.inputMethod = .telex
    cfg.settings.hotkey = .ctrlShift
    cfg.settings.modernOrthography = false
    cfg.settings.isEnabled = false
    cfg.perAppEnabled["com.apple.Terminal"] = false
    cfg.perAppEnabled["com.google.Chrome"] = true
    try store.save(cfg)

    let loaded = store.load()
    try expectEqual(loaded, cfg)
}

suite.test("VietnameseEngine simulates mixed Vietnamese and English sentence") {
    let eng = VietnameseEngine(settings: VietnameseSettings(inputMethod: .telexAndVni, hotkey: .ctrlShift, modernOrthography: true, freeMark: true, spellCheckEnabled: true, restoreOnEscape: true, standaloneWAsU: false))
    let typed = eng.simulate("Tooi ddang code Swift treen macOS vaf WordPress chajy nhanh hown ")
    try expectEqual(typed, "Tôi đang code Swift trên macOS và WordPress chạy nhanh hơn ")
}

suite.test("Native libproc scanLiveProcesses returns live processes without /bin/ps") {
    let procs = try ProcessScanner.scanLiveProcesses()
    try expect(!procs.isEmpty, "Should read live processes via Darwin libproc")
    let selfPID = ProcessInfo.processInfo.processIdentifier
    try expect(procs.contains(where: { $0.pid == selfPID && $0.rssBytes > 0 }), "Should detect current MacPulseTests process with RSS > 0")
}

suite.test("ProcessScanner assigns ProcessGuidance and safety levels accurately") {
    let raw = [
        RawProcessInfo(pid: 101, ppid: 1, cpuPercent: 72.0, rssBytes: 1_200_000_000, elapsed: "01:00", comm: "ChatGPT", args: "/Applications/ChatGPT.app/Contents/MacOS/ChatGPT"),
        RawProcessInfo(pid: 102, ppid: 1, cpuPercent: 12.0, rssBytes: 2_500_000_000, elapsed: "05:00", comm: "Google Chrome", args: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"),
        RawProcessInfo(pid: 103, ppid: 1, cpuPercent: 8.0, rssBytes: 150_000_000, elapsed: "10:00", comm: "9Remote", args: "/Applications/9Remote.app/Contents/MacOS/9Remote"),
        RawProcessInfo(pid: 104, ppid: 1, cpuPercent: 45.0, rssBytes: 80_000_000, elapsed: "02:00", comm: "replayd", args: "/usr/libexec/replayd"),
        RawProcessInfo(pid: 105, ppid: 1, cpuPercent: 5.0, rssBytes: 300_000_000, elapsed: "01:00", comm: "Google Chrome", args: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome --enable-automation --user-data-dir=/tmp/puppeteer_dev_chrome_profile-abc")
    ]
    let groups = ProcessScanner.aggregate(raw)

    let gpt = groups.first { $0.displayName == "ChatGPT" }
    try expect(gpt != nil, "ChatGPT group should exist")
    try expectEqual(gpt?.guidance.safetyLevel, .cautionSaveFirst)
    try expectEqual(gpt?.actionKind, .quitAppGracefully)
    try expectEqual(gpt?.bundleIdentifier, "com.openai.chat")
    try expect(gpt?.guidance.currentActivityHint.contains("72% CPU") == true, "Guidance should reflect dynamic CPU activity")

    let chrome = groups.first { $0.displayName == "Google Chrome" }
    try expectEqual(chrome?.actionKind, .inspectBrowserTabs)

    let remote = groups.first { $0.id.hasPrefix("remote:") }
    try expectEqual(remote?.guidance.safetyLevel, .remoteKeepAlive)

    let replayd = groups.first { $0.id == "sys:replayd" }
    try expectEqual(replayd?.guidance.safetyLevel, .systemProtected)

    let orphan = groups.first { $0.isOrphanAutomation }
    try expectEqual(orphan?.guidance.safetyLevel, .safeNow)
    try expectEqual(orphan?.actionKind, .killOrphanPuppeteer)
}

suite.test("HealthAnalyzer surfaces actionable close finding for overloaded user app and cleaner links") {
    let raw = [
        RawProcessInfo(pid: 201, ppid: 1, cpuPercent: 68.0, rssBytes: 1_500_000_000, elapsed: "01:00", comm: "ChatGPT", args: "/Applications/ChatGPT.app/Contents/MacOS/ChatGPT")
    ]
    let groups = ProcessScanner.aggregate(raw)
    let snap = SystemSnapshot(
        cpu: CPUMetrics(userPercent: 50, systemPercent: 28, idlePercent: 22, coreCount: 8, load1m: 6.0, load5m: 4.0, load15m: 3.0),
        memory: MemoryMetrics(
            totalBytes: 16 * 1_073_741_824,
            activeBytes: 5 * 1_073_741_824,
            inactiveBytes: 3 * 1_073_741_824,
            wiredBytes: 2 * 1_073_741_824,
            compressedBytes: 6 * 1_073_741_824,
            freeBytes: 400_000_000,
            purgeableBytes: 0,
            swapTotalBytes: 4_000_000_000,
            swapUsedBytes: 2_500_000_000,
            swapins: 10,
            swapouts: 20
        ),
        disk: DiskMetrics(totalBytes: 245_000_000_000, availableBytes: 18_000_000_000, usedBytes: 227_000_000_000)
    )
    let report = HealthAnalyzer.analyze(snapshot: snap, processGroups: groups)
    let gptFinding = report.findings.first { $0.id.contains("hot-user-app") }
    try expect(gptFinding != nil, "Should flag overloaded ChatGPT")
    try expectEqual(gptFinding?.actionLabel, "Đóng")
    try expectEqual(gptFinding?.recommendedAction, .quitAppGracefully)

    let ramFinding = report.findings.first { $0.id == "memory-compressor" }
    try expectEqual(ramFinding?.recommendedAction, .openCleanerTab)
    try expectEqual(ramFinding?.targetID, "ram")

    let diskFinding = report.findings.first { $0.id == "disk-low" }
    try expectEqual(diskFinding?.recommendedAction, .openCleanerTab)
    try expectEqual(diskFinding?.targetID, "ssd")
}

suite.test("CleanupScanner separates Cache vs Logs vs Heavy SSD Storage") {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("MacPulseCatTest-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let fm = FileManager.default
    let chromeCache = tmp.appendingPathComponent("Library/Caches/Google/Chrome")
    let opencodeDir = tmp.appendingPathComponent(".local/share/opencode")
    let localLogDir = tmp.appendingPathComponent("Local Sites/demo/logs")
    try fm.createDirectory(at: chromeCache, withIntermediateDirectories: true)
    try fm.createDirectory(at: opencodeDir, withIntermediateDirectories: true)
    try fm.createDirectory(at: localLogDir, withIntermediateDirectories: true)

    let payload200KB = Data(repeating: 0x41, count: 200_000)
    try payload200KB.write(to: chromeCache.appendingPathComponent("cache.bin"))
    let payload2MB = Data(repeating: 0x42, count: 2_000_000)
    try payload2MB.write(to: opencodeDir.appendingPathComponent("opencode.db"))
    try payload2MB.write(to: localLogDir.appendingPathComponent("error.log"))

    let scanner = CleanupScanner(homeDirectory: tmp, oversizedLogThresholdBytes: 1_000_000, inspectThresholdBytes: 1_000_000)
    let items = scanner.scan()

    let cacheItem = items.first { $0.id == "cache-chrome" }
    try expectEqual(cacheItem?.category, .cache)
    try expectEqual(cacheItem?.tier, .safeAutoClean)

    let logItem = items.first { $0.method == .truncateLogFile }
    try expectEqual(logItem?.category, .logsAndTrash)

    let heavyItem = items.first { $0.id == "inspect-opencode-db" }
    try expectEqual(heavyItem?.category, .storageHeavyData)
    try expectEqual(heavyItem?.tier, .inspectOnly)
}

suite.test("CleanupExecutor refuses to terminate self PID") {
    let selfPID = ProcessInfo.processInfo.processIdentifier
    let res = CleanupExecutor.terminatePIDs([selfPID], force: false)
    try expect(res.killed.isEmpty, "Must never terminate self PID")
    try expectEqual(res.failed, [selfPID])
}


suite.test("ProcessScanner detects Playwright headless Chrome while ignoring Remote Hub & CRD") {
    let pwArgs = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome --headless --no-startup-window --user-data-dir=/var/folders/T/playwright_chromiumdev_profile-d7EX9D --remote-debugging-pipe"
    try expect(ProcessScanner.isOrphanPuppeteerCommand(pwArgs), "Playwright headless Chrome must be flagged as orphan automation")

    let normalChrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    try expect(!ProcessScanner.isOrphanPuppeteerCommand(normalChrome), "Normal GUI Chrome must NOT be flagged as orphan")

    let remoteHub = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome --headless --user-data-dir=/Users/ducdung/.mac-remote-hub/chrome-profile --remote-debugging-pipe"
    try expect(!ProcessScanner.isOrphanPuppeteerCommand(remoteHub), "Remote Hub Chrome profile must be protected")

    let crd = "/Library/PrivilegedHelperTools/ChromeRemoteDesktopHost.app/Contents/MacOS/remoting_me2me_host"
    try expect(!ProcessScanner.isOrphanPuppeteerCommand(crd), "CRD host must never be flagged")
}

suite.test("CleanupExecutor.rescueAndCleanChrome removes broken SingletonLock & profile caches while keeping user data") {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("macpulse-chrome-rescue-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let fm = FileManager.default

    let chromeSupport = root.appendingPathComponent("Library/Application Support/Google/Chrome")
    let defaultProfile = chromeSupport.appendingPathComponent("Default")
    let profile2 = chromeSupport.appendingPathComponent("Profile 2")
    let grShader = chromeSupport.appendingPathComponent("GrShaderCache")
    let swCache = defaultProfile.appendingPathComponent("Service Worker/CacheStorage")
    let gpuCache = profile2.appendingPathComponent("GPUCache")

    try fm.createDirectory(at: grShader, withIntermediateDirectories: true)
    try fm.createDirectory(at: swCache, withIntermediateDirectories: true)
    try fm.createDirectory(at: gpuCache, withIntermediateDirectories: true)

    try Data(repeating: 0xAA, count: 120_000).write(to: grShader.appendingPathComponent("shader.bin"))
    try Data(repeating: 0xBB, count: 250_000).write(to: swCache.appendingPathComponent("sw.data"))
    try Data(repeating: 0xCC, count: 140_000).write(to: gpuCache.appendingPathComponent("gpu.bin"))

    // Important user data that MUST NOT be deleted
    let cookies = defaultProfile.appendingPathComponent("Cookies")
    let bookmarks = defaultProfile.appendingPathComponent("Bookmarks")
    try Data("cookies".utf8).write(to: cookies)
    try Data("bookmarks".utf8).write(to: bookmarks)

    // Broken symlink SingletonLock like macOS Chrome creates
    let lockSymlink = chromeSupport.appendingPathComponent("SingletonLock")
    try fm.createSymbolicLink(atPath: lockSymlink.path, withDestinationPath: "Mac-Mini.local-99999")
    let devPort = chromeSupport.appendingPathComponent("DevToolsActivePort")
    try Data("9222".utf8).write(to: devPort)

    let scanner = CleanupScanner(homeDirectory: root)
    let scanned = scanner.scan()
    let chromeItem = scanned.first { $0.id == "cache-chrome" }
    try expect(chromeItem != nil && (chromeItem?.sizeBytes ?? 0) >= 500_000, "Scanner must aggregate Profile GPU & Service Worker caches")

    let report = CleanupExecutor.rescueAndCleanChrome(homeDirectory: root, relaunch: false, skipProcessTermination: true)
    try expect(report.freedBytes >= 500_000, "Should free >= 500 KB of Chrome caches")
    try expect(report.removedLockFiles.contains("SingletonLock"), "Should remove broken SingletonLock symlink")
    try expect(report.removedLockFiles.contains("DevToolsActivePort"), "Should remove DevToolsActivePort")
    try expect(fm.fileExists(atPath: cookies.path), "Cookies MUST remain intact")
    try expect(fm.fileExists(atPath: bookmarks.path), "Bookmarks MUST remain intact")
}

suite.summaryAndExit()
