import Darwin
import Foundation
import SQLite3
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
    try expect(s1.memory.totalBytes >= 2 * 1_073_741_824, "RAM >= 2 GB")
    try expect(s1.cpu.coreCount >= 2, "coreCount >= 2")
    try expect(s1.disk.totalBytes > 10 * 1_073_741_824, "disk > 10 GB")
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
    let engNoSpell = VietnameseEngine(settings: VietnameseSettings(inputMethod: .telex, spellCheckEnabled: false, standaloneWAsU: false))
    try expectEqual(engNoSpell.simulate("worf "), "wò ")
}

suite.test("IME 31: Bracket shortcuts [ -> ơ, ] -> ư, u[ -> ươ, and double-tap undo") {
    let eng = VietnameseEngine(settings: VietnameseSettings(inputMethod: .telex, bracketShortcuts: true))
    try expectEqual(eng.simulate("m[ m] thu[cs th][ngf "), "mơ mư thước thường ")
    try expectEqual(eng.simulate("m[[ m]] "), "m[ m] ")
    try expectEqual(eng.simulate("{ } "), "Ơ Ư ")
}

suite.test("IME 32: Macros / Gõ tắt expands on space and preserves capitalization") {
    let eng = VietnameseEngine(settings: VietnameseSettings(inputMethod: .telex, macroEnabled: true))
    try expectEqual(eng.simulate("vn hn sg dc ko bt "), "Việt Nam Hà Nội Sài Gòn được không biết ")
    try expectEqual(eng.simulate("VN HN "), "VIỆT NAM HÀ NỘI ")
}


suite.test("IME 33: Comprehensive chat words & W-as-Ư tests") {
    let eng = VietnameseEngine(settings: VietnameseSettings(inputMethod: .telexAndVni))
    let cases: [(input: String, expected: String)] = [
        ("em thichs anh ", "em thích anh "),
        ("thichs ", "thích "),
        ("thisch ", "thích "),
        ("lichj ", "lịch "),
        ("tichs ", "tích "),
        ("nghijch ", "nghịch "),
        ("chinhs ", "chính "),
        ("minhf ", "mình "),
        ("tinhs ", "tính "),
        ("hinhf ", "hình "),
        ("huychs ", "huých "),
        ("chws ", "chứ "),
        ("chwx ", "chữ "),
        ("chwa ", "chưa "),
        ("nhw ", "như "),
        ("nhwngx ", "những "),
        ("nhwng ", "nhưng "),
        ("thws ", "thứ "),
        ("thwr ", "thử "),
        ("tws ", "tứ "),
        ("twf ", "từ "),
        ("swr ", "sử "),
        ("swj ", "sự "),
        ("bwax ", "bữa "),
        ("mwa ", "mưa "),
        ("ddwa ", "đưa "),
        ("trwf ", "trừ "),
        ("trwjc ", "trực "),
        ("ddwngs ", "đứng "),
        ("ddwngf ", "đừng "),
        ("mwngf ", "mừng "),
        ("dduwcs ", "đức "),
        ("thwcs ", "thức "),
        ("ngwoif ", "người "),
        ("cuwoif ", "cười "),
        ("tuwoi ", "tươi "),
        ("tuwois ", "tưới "),
        ("muwoif ", "mười "),
        ("chats ", "chát "),
        ("chast ", "chát "),
        ("gox tieengs Vieejt chuaanr EVKey ", "gõ tiếng Việt chuẩn EVKey ")
    ]

    for c in cases {
        let got = eng.simulate(c.input)
        try expectEqual(got, c.expected, "Failed on input '\(c.input)'")
    }
}

suite.test("IME 34: aa => â produces exact 1-backspace replacement and disabled mode cleanly bypasses") {
    let eng = VietnameseEngine(settings: VietnameseSettings(inputMethod: .telex))
    let a1 = eng.processCharacter("a")
    guard case .passthrough = a1 else {
        throw TestFailure.failed("First 'a' should be passthrough")
    }
    let a2 = eng.processCharacter("a")
    guard case .replace(let bs, let text) = a2 else {
        throw TestFailure.failed("Second 'a' should produce replace")
    }
    try expectEqual(bs, 1, "Should delete exactly 1 character for aa->â")
    try expectEqual(text, "â", "Should replace with 'â'")

    let disabledSettings = VietnameseSettings(isEnabled: false)
    let disabledEng = VietnameseEngine(settings: disabledSettings)
    let d1 = disabledEng.processCharacter("a")
    guard case .passthrough = d1 else {
        throw TestFailure.failed("Disabled engine should pass through 'a'")
    }
    let d2 = disabledEng.processCharacter("a")
    guard case .passthrough = d2 else {
        throw TestFailure.failed("Disabled engine should pass through 2nd 'a'")
    }
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
    try expectEqual(replayd?.guidance.safetyLevel, .safeNow, "Wedged replayd (45% CPU) must be safeNow to restart")
    try expectEqual(replayd?.actionKind, .restartReplayd)

    // Healthy low-CPU replayd remains systemProtected
    let healthyReplayd = ProcessScanner.aggregate([
        RawProcessInfo(pid: 109, ppid: 1, cpuPercent: 1.5, rssBytes: 20_000_000, elapsed: "02:00", comm: "replayd", args: "/usr/libexec/replayd")
    ]).first { $0.id == "sys:replayd" }
    try expectEqual(healthyReplayd?.guidance.safetyLevel, .systemProtected)
    try expectEqual(healthyReplayd?.actionKind, ProcessActionKind.none)

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

suite.test("CleanupScanner separates Cache vs Logs vs Heavy SSD Storage and AI Garbage") {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("MacPulseCatTest-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let fm = FileManager.default
    let chromeCache = tmp.appendingPathComponent("Library/Caches/Google/Chrome")
    let cursorLogs = tmp.appendingPathComponent("Library/Application Support/Cursor/logs")
    let opencodeDir = tmp.appendingPathComponent(".local/share/opencode")
    let localLogDir = tmp.appendingPathComponent("Local Sites/demo/logs")
    try fm.createDirectory(at: chromeCache, withIntermediateDirectories: true)
    try fm.createDirectory(at: cursorLogs, withIntermediateDirectories: true)
    try fm.createDirectory(at: opencodeDir, withIntermediateDirectories: true)
    try fm.createDirectory(at: localLogDir, withIntermediateDirectories: true)

    let payload200KB = Data(repeating: 0x41, count: 200_000)
    try payload200KB.write(to: chromeCache.appendingPathComponent("cache.bin"))
    let payload100KB = Data(repeating: 0x44, count: 100_000)
    try payload100KB.write(to: cursorLogs.appendingPathComponent("cursor.log"))
    let payload2MB = Data(repeating: 0x42, count: 2_000_000)
    try payload2MB.write(to: opencodeDir.appendingPathComponent("opencode.db"))
    try payload2MB.write(to: localLogDir.appendingPathComponent("error.log"))

    let scanner = CleanupScanner(homeDirectory: tmp, oversizedLogThresholdBytes: 1_000_000, inspectThresholdBytes: 1_000_000)
    let items = scanner.scan()

    let cacheItem = items.first { $0.id == "cache-chrome" }
    try expectEqual(cacheItem?.category, .cache)
    try expectEqual(cacheItem?.tier, .safeAutoClean)

    let aiItem = items.first { $0.id == "cache-cursor-ai" }
    try expectEqual(aiItem?.category, .aiGarbage)
    try expectEqual(aiItem?.tier, .safeAutoClean)

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

suite.test("CleanupExecutor.rescueAndCleanChrome removes broken SingletonLock & OS cache while strictly preserving Extension Service Workers and user data") {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("macpulse-chrome-rescue-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let fm = FileManager.default

    let chromeCache = root.appendingPathComponent("Library/Caches/Google/Chrome/Default/Cache")
    let chromeSupport = root.appendingPathComponent("Library/Application Support/Google/Chrome")
    let defaultProfile = chromeSupport.appendingPathComponent("Default")
    let swCache = defaultProfile.appendingPathComponent("Service Worker/CacheStorage")
    let extDir = defaultProfile.appendingPathComponent("Extensions/aapocclcgogkmnuohehaiipmnkfkgcko")

    try fm.createDirectory(at: chromeCache, withIntermediateDirectories: true)
    try fm.createDirectory(at: swCache, withIntermediateDirectories: true)
    try fm.createDirectory(at: extDir, withIntermediateDirectories: true)

    // OS-level purgeable cache
    try Data(repeating: 0xAA, count: 550_000).write(to: chromeCache.appendingPathComponent("data_0"))

    // Critical extension & Service Worker files that MUST NOT be touched
    let swData = swCache.appendingPathComponent("sw.data")
    try Data(repeating: 0xBB, count: 250_000).write(to: swData)
    let extManifest = extDir.appendingPathComponent("manifest.json")
    try Data("{\"name\":\"Extension\"}".utf8).write(to: extManifest)

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
    try expect(chromeItem != nil && (chromeItem?.sizeBytes ?? 0) >= 500_000, "Scanner must detect Chrome OS cache")

    let report = CleanupExecutor.rescueAndCleanChrome(homeDirectory: root, relaunch: false, skipProcessTermination: true)
    try expect(report.freedBytes >= 500_000, "Should free >= 500 KB of Chrome OS cache")
    try expect(report.removedLockFiles.contains("SingletonLock"), "Should remove broken SingletonLock symlink")
    try expect(report.removedLockFiles.contains("DevToolsActivePort"), "Should remove DevToolsActivePort")

    // VERIFY: Extensions and Service Workers are 100% untouched!
    try expect(fm.fileExists(atPath: swData.path), "Extension Service Worker data MUST remain intact")
    try expect(fm.fileExists(atPath: extManifest.path), "Extension manifest MUST remain intact")
    try expect(fm.fileExists(atPath: cookies.path), "Cookies MUST remain intact")
    try expect(fm.fileExists(atPath: bookmarks.path), "Bookmarks MUST remain intact")
}

suite.test("ProcessScanner and CleanupExecutor handle stuck Chrome renderer processes") {
    let mainProc = RawProcessInfo(pid: 2001, ppid: 1, cpuPercent: 2.0, rssBytes: 500_000_000, elapsed: "10:00", comm: "Google Chrome", args: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
    let gpuProc = RawProcessInfo(pid: 2002, ppid: 2001, cpuPercent: 5.0, rssBytes: 150_000_000, elapsed: "10:00", comm: "Google Chrome Helper", args: "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper (GPU).app/Contents/MacOS/Google Chrome Helper (GPU) --type=gpu-process")
    let rendererProc = RawProcessInfo(pid: 2003, ppid: 2001, cpuPercent: 35.0, rssBytes: 400_000_000, elapsed: "02:00", comm: "Google Chrome Helper (Renderer)", args: "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer) --type=renderer --site-per-process")

    try expect(!ProcessScanner.isChromeRendererProcess(mainProc), "Main browser is not a renderer")
    try expect(!ProcessScanner.isChromeRendererProcess(gpuProc), "GPU process is not a renderer")
    try expect(ProcessScanner.isChromeRendererProcess(rendererProc), "Renderer process must be recognized")
}

suite.test("IME 35: ddwng -> đưng/đừng and standalone W as Ư default behavior") {
    let eng = VietnameseEngine(settings: VietnameseSettings(inputMethod: .telex))
    try expectEqual(eng.simulate("aw"), "ă", "aw should produce ă")
    try expectEqual(eng.simulate("w"), "ư", "w standalone should produce ư by default")
    try expectEqual(eng.simulate("a w"), "a ư", "a w should produce a ư")
    try expectEqual(eng.simulate("ddw"), "đư", "ddw should produce đư")
    try expectEqual(eng.simulate("ddwng"), "đưng", "ddwng should produce đưng")
    try expectEqual(eng.simulate("ddwngf"), "đừng", "ddwngf should produce đừng")
    try expectEqual(eng.simulate("dw"), "dư", "dw should produce dư")
    try expectEqual(eng.simulate("tw"), "tư", "tw should produce tư")

    // Verify onset + W sends at least 1 backspace to avoid dropping characters
    let engAction = VietnameseEngine(settings: VietnameseSettings(inputMethod: .telex))
    _ = engAction.processCharacter("d")
    _ = engAction.processCharacter("d") // now "đ"
    let wAction = engAction.processCharacter("w")
    guard case .replace(let bs, let text) = wAction else {
        throw TestFailure.failed("w after đ should produce replace action")
    }
    try expect(bs >= 1, "Backspace count must be >= 1 to wake the text field (was \(bs))")
    try expectEqual(text, "đư", "Replacement text should be 'đư'")
}

suite.test("IME 36: Smart English words auto-restore on delimiter") {
    let eng = VietnameseEngine(settings: VietnameseSettings(inputMethod: .telex, smartEnglishRestore: true))
    try expectEqual(eng.simulate("post "), "post ", "post should auto-restore")
    try expectEqual(eng.simulate("user "), "user ", "user should auto-restore")
    try expectEqual(eng.simulate("reset "), "reset ", "reset should auto-restore")
    try expectEqual(eng.simulate("status "), "status ", "status should auto-restore")
    try expectEqual(eng.simulate("admin "), "admin ", "admin should auto-restore")
    try expectEqual(eng.simulate("format "), "format ", "format should auto-restore")
    try expectEqual(eng.simulate("docker "), "docker ", "docker should auto-restore")
    try expectEqual(eng.simulate("react "), "react ", "react should auto-restore")
    try expectEqual(eng.simulate("true "), "true ", "true should auto-restore")
    try expectEqual(eng.simulate("class "), "class ", "class should auto-restore")
    try expectEqual(eng.simulate("google "), "google ", "google should auto-restore")
    // Real Vietnamese words must NOT be restored:
    try expectEqual(eng.simulate("toans "), "toán ", "toán must remain accented")
    try expectEqual(eng.simulate("nguoiwf "), "người ", "người must remain accented")
    try expectEqual(eng.simulate("dduocwj "), "được ", "được must remain accented")
}

suite.test("IME 37: Quick Telex onset expansion and 3-tap undo") {
    let eng = VietnameseEngine(settings: VietnameseSettings(inputMethod: .telex, quickTelex: true))
    try expectEqual(eng.simulate("ccaos "), "cháo ", "cc should expand to ch")
    try expectEqual(eng.simulate("kkoong "), "không ", "kk should expand to kh")
    try expectEqual(eng.simulate("nnuoiwf "), "người ", "nn should expand to ng")
    try expectEqual(eng.simulate("tteef "), "thề ", "tt should expand to th")
    try expectEqual(eng.simulate("ggas "), "giá ", "gg should expand to gi")
    try expectEqual(eng.simulate("ppair "), "phải ", "pp should expand to ph")
    try expectEqual(eng.simulate("qqas "), "quá ", "qq should expand to qu")
    // 3-tap undo
    try expectEqual(eng.simulate("ccc "), "ccc ", "ccc should undo to ccc")
    try expectEqual(eng.simulate("kkk "), "kkk ", "kkk should undo to kkk")
}

suite.test("IME 38: Smart Auto-Capitalization after sentence delimiters") {
    let eng = VietnameseEngine(settings: VietnameseSettings(inputMethod: .telex, autoCapitalize: true))
    try expectEqual(eng.simulate("chaof banj. hoom nay ddepj trowif! chungs ta ddi? ok. "), "chào bạn. Hôm nay đẹp trời! Chúng ta đi? Ok. ")
}

suite.test("IME 39: Expanded modern macros") {
    let eng = VietnameseEngine(settings: VietnameseSettings(inputMethod: .telex, macroEnabled: true))
    try expectEqual(eng.simulate("ad sp nv kh cty r nt tl "), "admin sản phẩm nhân viên khách hàng công ty rồi nhắn tin trả lời ")
    try expectEqual(eng.simulate("Cty Kh Sp "), "Công ty Khách hàng Sản phẩm ")
}


suite.test("IME 40: Stability of coongj -> cộng and quickTelex opt-in") {
    let engDefault = VietnameseEngine(settings: VietnameseSettings(inputMethod: .telex))
    try expectEqual(engDefault.simulate("coongj "), "cộng ")
    try expectEqual(engDefault.simulate("ccoong "), "ccoong ", "Quick Telex must be off by default so cc does not become ch")

    let engQuick = VietnameseEngine(settings: VietnameseSettings(inputMethod: .telex, quickTelex: true))
    try expectEqual(engQuick.simulate("ccoong "), "chông ")
}

suite.test("AITokenMonitor: detects ChatGPT/Codex and excludes Antigravity per user preference") {
    let tmpCache = FileManager.default.temporaryDirectory.appendingPathComponent("MacPulseAICache-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: tmpCache) }
    let monitor = AITokenMonitor(cacheFileURL: tmpCache)
    let snap = monitor.scanAll()
    try expectEqual(snap.providers.count, 3)
    try expect(snap.antigravity == nil, "Antigravity must be excluded from scanAll()")
    let chatgpt = snap.providers.first { $0.providerType == .openaiCodex }
    try expect(chatgpt != nil, "ChatGPT provider must be present")
    if let gpt = chatgpt, gpt.isDetected, gpt.sourceState == .live {
        try expect(gpt.fiveHourQuota != nil, "ChatGPT must have five-hour quota when live")
        try expect(gpt.weeklyQuota != nil, "ChatGPT must have weekly quota when live")
    }
}

suite.test("VietnameseAppDetector recognizes VPS, Remote Desktop and Terminal apps") {
    // VPS & Remote Desktop
    try expect(VietnameseAppDetector.isVPSOrRemoteApp(bundleID: "com.microsoft.rdc.macos"), "Microsoft Remote Desktop should be detected as VPS")
    try expect(VietnameseAppDetector.isVPSOrRemoteApp(bundleID: "com.microsoft.rdc.macos", appName: "Windows App"), "Windows App with com.microsoft.rdc.macos should be detected as VPS")
    try expect(VietnameseAppDetector.isVPSOrRemoteApp(bundleID: "com.microsoft.WindowsApp", appName: "Windows App"), "Windows App with com.microsoft.WindowsApp should be detected as VPS")
    try expect(VietnameseAppDetector.isVPSOrRemoteApp(bundleID: "unknown.bundle", appName: "Windows App"), "Windows App by name should be detected as VPS")
    try expect(VietnameseAppDetector.isVPSOrRemoteApp(bundleID: "com.microsoft.rdc.mac"), "Windows App should be detected as VPS")
    try expect(VietnameseAppDetector.isVPSOrRemoteApp(bundleID: "com.philandro.anydesk"), "AnyDesk should be detected as VPS")
    try expect(VietnameseAppDetector.isVPSOrRemoteApp(bundleID: "com.carriez.rustdesk"), "RustDesk should be detected as VPS")
    try expect(VietnameseAppDetector.isVPSOrRemoteApp(bundleID: "com.realvnc.vncviewer"), "RealVNC should be detected as VPS")
    try expect(VietnameseAppDetector.isVPSOrRemoteApp(bundleID: "com.termius-desktop"), "Termius should be detected as VPS")
    try expect(VietnameseAppDetector.isVPSOrRemoteApp(bundleID: "com.lemonmojo.RoyalTSX.App"), "Royal TSX should be detected as VPS")
    try expect(VietnameseAppDetector.isVPSOrRemoteApp(bundleID: "custom.app", appName: "AnyDesk"), "AnyDesk by name should be detected")

    // Non-VPS apps must NOT match
    try expect(!VietnameseAppDetector.isVPSOrRemoteApp(bundleID: "com.google.Chrome"), "Chrome is not a VPS app")
    try expect(!VietnameseAppDetector.isVPSOrRemoteApp(bundleID: "org.telegram.desktop"), "Telegram is not a VPS app")
    try expect(!VietnameseAppDetector.isVPSOrRemoteApp(bundleID: "com.apple.Notes"), "Notes is not a VPS app")

    // Terminal apps
    try expect(VietnameseAppDetector.isTerminalApp(bundleID: "com.apple.Terminal"), "Apple Terminal should be detected")
    try expect(VietnameseAppDetector.isTerminalApp(bundleID: "com.googlecode.iterm2"), "iTerm2 should be detected")
    try expect(VietnameseAppDetector.isTerminalApp(bundleID: "dev.warp.Warp-Stable"), "Warp should be detected")

    // Exclusion computation
    var settings = VietnameseSettings()
    settings.autoBypassVPSAndRemote = true
    settings.autoBypassTerminal = true
    try expect(VietnameseAppDetector.computeIsAppExcluded(bundleID: "com.microsoft.rdc.macos", appName: "", settings: settings), "RDC must be excluded when autoBypassVPS is true")
    try expect(VietnameseAppDetector.computeIsAppExcluded(bundleID: "com.apple.Terminal", appName: "", settings: settings), "Terminal must be excluded when autoBypassTerminal is true")

    // Disabling autoBypassVPS
    settings.autoBypassVPSAndRemote = false
    try expect(!VietnameseAppDetector.computeIsAppExcluded(bundleID: "com.microsoft.rdc.macos", appName: "", settings: settings), "RDC not excluded when autoBypassVPS is false")

    // Custom excluded list
    settings.excludedBundleIDs = ["com.custom.vpswrapper"]
    try expect(VietnameseAppDetector.computeIsAppExcluded(bundleID: "com.custom.vpswrapper", appName: "", settings: settings), "Custom excluded bundle must be bypassed")
}

suite.test("IME 41: Natural typing of English prefixes and words (reset, result, exit, user, design, password)") {
    let eng = VietnameseEngine(settings: VietnameseSettings(inputMethod: .telex))
    // Direct in-flight typing without delimiter
    try expectEqual(eng.simulate("reset"), "reset")
    try expectEqual(eng.simulate("result"), "result")
    try expectEqual(eng.simulate("exit"), "exit")
    try expectEqual(eng.simulate("user"), "user")
    try expectEqual(eng.simulate("design"), "design")

    // Typing with space delimiter
    try expectEqual(eng.simulate("reset "), "reset ")
    try expectEqual(eng.simulate("resset "), "reset ")
    try expectEqual(eng.simulate("result "), "result ")
    try expectEqual(eng.simulate("ressult "), "result ")
    try expectEqual(eng.simulate("pause"), "pause")
    try expectEqual(eng.simulate("pause "), "pause ")
    try expectEqual(eng.simulate("pausse"), "pause")
    try expectEqual(eng.simulate("pausse "), "pause ")
    try expectEqual(eng.simulate("cause "), "cause ")
    try expectEqual(eng.simulate("causse "), "cause ")
    // Typing with space delimiter
    try expectEqual(eng.simulate("reset "), "reset ")
    try expectEqual(eng.simulate("resset "), "reset ")
    try expectEqual(eng.simulate("result "), "result ")
    try expectEqual(eng.simulate("ressult "), "result ")
    try expectEqual(eng.simulate("pause"), "pause")
    try expectEqual(eng.simulate("pause "), "pause ")
    try expectEqual(eng.simulate("pausse"), "pause")
    try expectEqual(eng.simulate("pausse "), "pause ")
    try expectEqual(eng.simulate("cause "), "cause ")
    try expectEqual(eng.simulate("causse "), "cause ")
    try expectEqual(eng.simulate("house "), "house ")
    try expectEqual(eng.simulate("case "), "case ")
    try expectEqual(eng.simulate("casse "), "case ")
    try expectEqual(eng.simulate("base "), "base ")
    try expectEqual(eng.simulate("basse "), "base ")
    try expectEqual(eng.simulate("safe "), "safe ")
    try expectEqual(eng.simulate("saffe "), "safe ")
    try expectEqual(eng.simulate("life "), "life ")
    try expectEqual(eng.simulate("liffe "), "life ")
    try expectEqual(eng.simulate("care "), "care ")
    try expectEqual(eng.simulate("carre "), "care ")
    try expectEqual(eng.simulate("more "), "more ")
    try expectEqual(eng.simulate("morre "), "more ")
    try expectEqual(eng.simulate("password "), "password ")
    try expectEqual(eng.simulate("different "), "different ")
    try expectEqual(eng.simulate("coffee "), "coffee ")
    try expectEqual(eng.simulate("error "), "error ")
}

suite.test("IME 42: Comprehensive quá and qu-onset typing resilience") {
    // 1. Quick Telex enabled (deterministic settings — never depend on host machine's user store)
    let engQuick = VietnameseEngine(settings: VietnameseSettings(inputMethod: .telex, quickTelex: true))

    try expectEqual(engQuick.simulate("quas"), "quá")
    try expectEqual(engQuick.simulate("quas "), "quá ")
    try expectEqual(engQuick.simulate("\"quas\""), "\"quá\"")
    try expectEqual(engQuick.simulate("quas\""), "quá\"")
    try expectEqual(engQuick.simulate("'quas'"), "'quá'")
    try expectEqual(engQuick.simulate("quas,"), "quá,")
    try expectEqual(engQuick.simulate("quas."), "quá.")
    try expectEqual(engQuick.simulate("qqas"), "quá")
    try expectEqual(engQuick.simulate("qqas "), "quá ")
    try expectEqual(engQuick.simulate("qas"), "quá")
    try expectEqual(engQuick.simulate("qas "), "quá ")
    try expectEqual(engQuick.simulate("qan "), "quan ")
    try expectEqual(engQuick.simulate("qen "), "quen ")
    try expectEqual(engQuick.simulate("qes "), "qué ")
    try expectEqual(engQuick.simulate("qy "), "quy ")
    try expectEqual(engQuick.simulate("qys "), "quý ")
    try expectEqual(engQuick.simulate("qusa"), "quá")
    try expectEqual(engQuick.simulate("qusa "), "quá ")

    // 2. Default Telex settings (quickTelex = false)
    let telexDefault = VietnameseEngine(settings: VietnameseSettings(inputMethod: .telex))
    try expectEqual(telexDefault.simulate("quas"), "quá")
    try expectEqual(telexDefault.simulate("quas "), "quá ")
    try expectEqual(telexDefault.simulate("qusa"), "quá")
    try expectEqual(telexDefault.simulate("qusa "), "quá ")

    // 3. Hybrid Telex + VNI
    let telexVni = VietnameseEngine(settings: VietnameseSettings(inputMethod: .telexAndVni))
    try expectEqual(telexVni.simulate("quas"), "quá")
    try expectEqual(telexVni.simulate("quas "), "quá ")
    try expectEqual(telexVni.simulate("qua1"), "quá")
    try expectEqual(telexVni.simulate("qua1 "), "quá ")
    try expectEqual(telexVni.simulate("qu1a"), "quá")
    try expectEqual(telexVni.simulate("qu1a "), "quá ")
}

suite.test("IME 43: Test and commonly mistyped English words natural typing") {
    let engSaved = VietnameseEngine(settings: VietnameseSettings(inputMethod: .telex))

    // Direct in-flight typing & double-key undo typing
    try expectEqual(engSaved.simulate("test"), "test")
    try expectEqual(engSaved.simulate("test "), "test ")
    try expectEqual(engSaved.simulate("tesst"), "test")
    try expectEqual(engSaved.simulate("tesst "), "test ")

    try expectEqual(engSaved.simulate("best"), "best")
    try expectEqual(engSaved.simulate("best "), "best ")
    try expectEqual(engSaved.simulate("besst"), "best")
    try expectEqual(engSaved.simulate("besst "), "best ")

    try expectEqual(engSaved.simulate("list"), "list")
    try expectEqual(engSaved.simulate("list "), "list ")
    try expectEqual(engSaved.simulate("lisst"), "list")
    try expectEqual(engSaved.simulate("lisst "), "list ")

    try expectEqual(engSaved.simulate("post"), "post")
    try expectEqual(engSaved.simulate("post "), "post ")
    try expectEqual(engSaved.simulate("posst"), "post")
    try expectEqual(engSaved.simulate("posst "), "post ")

    try expectEqual(engSaved.simulate("fast"), "fast")
    try expectEqual(engSaved.simulate("fast "), "fast ")
    try expectEqual(engSaved.simulate("fasst "), "fast ")
    try expectEqual(engSaved.simulate("last"), "last")
    try expectEqual(engSaved.simulate("lasst"), "last")
    try expectEqual(engSaved.simulate("cost"), "cost")
    try expectEqual(engSaved.simulate("cosst"), "cost")
    try expectEqual(engSaved.simulate("just"), "just")
    try expectEqual(engSaved.simulate("just "), "just ")
    try expectEqual(engSaved.simulate("jusst "), "just ")
    try expectEqual(engSaved.simulate("must"), "must")
    try expectEqual(engSaved.simulate("musst"), "must")

    // Inflections & Developer words
    try expectEqual(engSaved.simulate("testing "), "testing ")
    try expectEqual(engSaved.simulate("tested "), "tested ")
    try expectEqual(engSaved.simulate("posting "), "posting ")
    try expectEqual(engSaved.simulate("listing "), "listing ")

    // Intentional double stems must be preserved
    try expectEqual(engSaved.simulate("pass "), "pass ")
    try expectEqual(engSaved.simulate("password "), "password ")
    try expectEqual(engSaved.simulate("different "), "different ")
    try expectEqual(engSaved.simulate("coffee "), "coffee ")
    try expectEqual(engSaved.simulate("message "), "message ")
    try expectEqual(engSaved.simulate("error "), "error ")
}

suite.test("IME 44: Comprehensive typing for 'vừa', 'vườn', 'cửa', 'lửa', 'người', 'được', 'nữa', 'mưa'") {
    let engSaved = VietnameseEngine(settings: VietnameseSettings(inputMethod: .telex))

    try expectEqual(engSaved.simulate("vuwaf"), "vừa")
    try expectEqual(engSaved.simulate("vuwaf "), "vừa ")
    try expectEqual(engSaved.simulate("vuawf"), "vừa")
    try expectEqual(engSaved.simulate("vuawf "), "vừa ")
    try expectEqual(engSaved.simulate("vuafw"), "vừa")
    try expectEqual(engSaved.simulate("vuafw "), "vừa ")
    try expectEqual(engSaved.simulate("vwaf"), "vừa")
    try expectEqual(engSaved.simulate("vwaf "), "vừa ")
    try expectEqual(engSaved.simulate("vuwfa"), "vừa")
    try expectEqual(engSaved.simulate("vuwfa "), "vừa ")

    try expectEqual(engSaved.simulate("cuwar"), "cửa")
    try expectEqual(engSaved.simulate("cuawr"), "cửa")
    try expectEqual(engSaved.simulate("cuarw"), "cửa")
    try expectEqual(engSaved.simulate("luwar"), "lửa")
    try expectEqual(engSaved.simulate("luawr"), "lửa")
    try expectEqual(engSaved.simulate("nuwax"), "nữa")
    try expectEqual(engSaved.simulate("nuawx"), "nữa")
    try expectEqual(engSaved.simulate("muwa"), "mưa")
    try expectEqual(engSaved.simulate("muaw"), "mưa")
    try expectEqual(engSaved.simulate("ddwocj"), "được")
    try expectEqual(engSaved.simulate("nguwoif"), "người")
    try expectEqual(engSaved.simulate("nguoifw"), "người")
    try expectEqual(engSaved.simulate("nguoiwf"), "người")

    try expectEqual(engSaved.simulate("vuonwf"), "vườn")
    try expectEqual(engSaved.simulate("vuonfw"), "vườn")
    try expectEqual(engSaved.simulate("vuownf"), "vườn")
    try expectEqual(engSaved.simulate("vuwonf"), "vườn")
    try expectEqual(engSaved.simulate("vuongwf"), "vường")
    try expectEqual(engSaved.simulate("vuongfw"), "vường")
}

suite.test("VietnameseAppDetector identifies browsers and search apps accurately") {
    try expect(VietnameseAppDetector.isBrowserOrSearchApp(bundleID: "com.google.Chrome"), "Google Chrome should be identified as browser")
    try expect(VietnameseAppDetector.isBrowserOrSearchApp(bundleID: "com.apple.Safari"), "Safari should be identified as browser")
    try expect(VietnameseAppDetector.isBrowserOrSearchApp(bundleID: "com.apple.Spotlight"), "Spotlight should be identified as browser/search")
    try expect(VietnameseAppDetector.isBrowserOrSearchApp(bundleID: "com.microsoft.edgemac"), "Edge should be identified as browser")
    try expect(VietnameseAppDetector.isBrowserOrSearchApp(bundleID: "com.brave.Browser"), "Brave should be identified as browser")
    try expect(VietnameseAppDetector.isBrowserOrSearchApp(bundleID: "company.thebrowser.Browser"), "Arc should be identified as browser")
    try expect(!VietnameseAppDetector.isBrowserOrSearchApp(bundleID: "com.apple.Terminal"), "Terminal should not be identified as browser")
    try expect(!VietnameseAppDetector.isBrowserOrSearchApp(bundleID: "com.microsoft.WindowsApp"), "Windows App should not be identified as browser")
}

suite.test("ProcessScanner identifies agent-browser and OpenMausBot automation correctly") {
    // 1. agent-browser CLI
    let agentBrowserComm = "agent-browser"
    let agentBrowserArgs = "/Applications/OpenMausBot.app/Contents/Resources/browser-engine/agent-browser mcp --tools core --no-webmcp"
    try expect(ProcessScanner.isOrphanPuppeteerCommand(agentBrowserArgs, comm: agentBrowserComm), "agent-browser binary should be recognized as orphan automation")

    // 2. OpenMausBot headless Chrome
    let openMausArgs = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome --headless=new --user-data-dir=/Users/ducdung/.openmausbot/agent-browser-profiles/c7bafa6b11f3ad680ce7f3c6438d425d --remote-debugging-port=0"
    try expect(ProcessScanner.isOrphanPuppeteerCommand(openMausArgs, comm: "Google Chrome"), "OpenMausBot headless Chrome should be recognized as orphan automation")

    // 3. Regular Google Chrome must NOT be flagged
    let regularChromeArgs = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    try expect(!ProcessScanner.isOrphanPuppeteerCommand(regularChromeArgs, comm: "Google Chrome"), "Normal user Google Chrome should NEVER be flagged as automation")

    // 4. Chrome Remote Desktop must NOT be flagged
    let remotingArgs = "/Library/PrivilegedHelperTools/remoting_me2me_host --user-data-dir=/Users/ducdung/.mac-remote-hub/chrome-profile"
    try expect(!ProcessScanner.isOrphanPuppeteerCommand(remotingArgs, comm: "remoting_me2me_host"), "Remote Desktop must never be flagged")
}

suite.test("CleanupExecutor discovers and cleans automation lock files without touching regular chrome") {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("MacPulseAutoLockTest-\(UUID().uuidString)")
    let fm = FileManager.default
    defer { try? fm.removeItem(at: tmp) }

    let profileSub = tmp.appendingPathComponent(".openmausbot/agent-browser-profiles/test-profile-hash")
    try fm.createDirectory(at: profileSub, withIntermediateDirectories: true)

    let lock1 = profileSub.appendingPathComponent("SingletonLock")
    let lock2 = profileSub.appendingPathComponent("DevToolsActivePort")
    try "test-lock".write(to: lock1, atomically: true, encoding: .utf8)
    try "9222\n/devtools/browser/abc".write(to: lock2, atomically: true, encoding: .utf8)

    let locks = CleanupExecutor.automationProfileLockPaths(homeDirectory: tmp)
    try expectEqual(locks.count, 2)
    try expect(locks.contains { $0.lastPathComponent == "SingletonLock" })
    try expect(locks.contains { $0.lastPathComponent == "DevToolsActivePort" })

    // Test rescue and reset cleans these lock files
    let report = CleanupExecutor.rescueAndResetBrowserAutomation(homeDirectory: tmp)
    try expect(report.removedLockFiles.contains("SingletonLock"), "SingletonLock should be removed")
    try expect(report.removedLockFiles.contains("DevToolsActivePort"), "DevToolsActivePort should be removed")
    try expect(!fm.fileExists(atPath: lock1.path), "Lock 1 should not exist on disk")
    try expect(!fm.fileExists(atPath: lock2.path), "Lock 2 should not exist on disk")
}

suite.test("v2.0: AITokenMonitor separates Today, 5h, and 7d tokens accurately across multi-day transcripts") {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("MacPulseAITokTest-\(UUID().uuidString)")
    let fm = FileManager.default
    defer { try? fm.removeItem(at: tmp) }

    let now = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date()
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime]

    let t1 = iso.string(from: now.addingTimeInterval(-600))        // 10 mins ago (Today + 5h + 7d)
    let t2 = iso.string(from: now.addingTimeInterval(-2 * 86400))  // 2 days ago (7d only, NOT Today, NOT 5h)
    let t3 = iso.string(from: now.addingTimeInterval(-10 * 86400)) // 10 days ago (Outside 7d)

    let logDir = tmp.appendingPathComponent("brain/conv-1/.system_generated/logs")
    try fm.createDirectory(at: logDir, withIntermediateDirectories: true)
    let lines = [
        "{\"type\":\"PLANNER_RESPONSE\",\"created_at\":\"\(t1)\",\"input_tokens\":1000,\"output_tokens\":200,\"cache_read_tokens\":300}",
        "{\"type\":\"PLANNER_RESPONSE\",\"created_at\":\"\(t2)\",\"input_tokens\":4000,\"output_tokens\":500,\"cache_read_tokens\":0}",
        "{\"type\":\"PLANNER_RESPONSE\",\"created_at\":\"\(t3)\",\"input_tokens\":9000,\"output_tokens\":1000,\"cache_read_tokens\":0}"
    ].joined(separator: "\n")
    try lines.write(to: logDir.appendingPathComponent("transcript.jsonl"), atomically: true, encoding: .utf8)

    let usage = AITokenMonitor.scanAntigravityTranscriptTokens(agyDir: tmp.path, now: now)
    try expectEqual(usage.totalToday, 1500)
    try expectEqual(usage.tokens5H, 1500)
    try expectEqual(usage.tokens7D, 6000)
    try expectEqual(usage.turnsToday, 1)
    try expectEqual(usage.sessionsToday, 1)
}

suite.test("v2.0: AITokenMonitor never fabricates fake 20% weekly quota when ChatGPT is offline without cache") {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("MacPulseChatGPTOffline-\(UUID().uuidString)")
    let fm = FileManager.default
    defer { try? fm.removeItem(at: tmp) }

    let codexDir = tmp.appendingPathComponent(".codex")
    try fm.createDirectory(at: codexDir, withIntermediateDirectories: true)
    // No auth.json -> offline with empty isolated cache
    let monitor = AITokenMonitor(cacheFileURL: tmp.appendingPathComponent("cache.json"))
    let metrics = monitor.scanOpenAICodex(home: tmp.path, today: "2026-11-25")
    try expect(metrics.isDetected, "Should detect .codex directory")
    try expectEqual(metrics.sourceState, .offline)
    try expect(metrics.fiveHourQuota == nil, "Must not fabricate fake 5h quota when offline without cache")
    try expect(metrics.weeklyQuota == nil, "Must not fabricate fake 20% weekly quota when offline without cache")
}

suite.test("v2.0: CleanupScanner detects Brave, Antigravity ShipIt, OpenMausBot caches and has zero duplicate Xcode entries") {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("MacPulseCleanV2-\(UUID().uuidString)")
    let fm = FileManager.default
    defer { try? fm.removeItem(at: tmp) }

    let payload = Data(repeating: 0x55, count: 120_000)
    let dirs = [
        "Library/Caches/BraveSoftware",
        "Library/Caches/Firefox",
        "Library/Caches/com.google.antigravity.ShipIt",
        "Library/Caches/openmausbot-updater",
        ".openmausbot/agent-browser-profiles/abc123/Default/Cache",
        "Library/Developer/Xcode/DerivedData"
    ]
    for rel in dirs {
        let u = tmp.appendingPathComponent(rel)
        try fm.createDirectory(at: u, withIntermediateDirectories: true)
        try payload.write(to: u.appendingPathComponent("data.bin"))
    }
    // Also place a protected Cookies file inside bot profile that must NOT be cleaned
    let cookiesURL = tmp.appendingPathComponent(".openmausbot/agent-browser-profiles/abc123/Default/Cookies")
    try payload.write(to: cookiesURL)

    let scanner = CleanupScanner(homeDirectory: tmp, oversizedLogThresholdBytes: 1024, inspectThresholdBytes: 50_000)
    let found = scanner.scan()
    let ids = Set(found.map(\.id))

    try expect(ids.contains("cache-brave"), "Should detect Brave Browser cache")
    try expect(ids.contains("cache-firefox"), "Should detect Firefox cache")
    try expect(ids.contains("cache-gemini-ai"), "Should detect Antigravity ShipIt cache")
    try expect(ids.contains("cache-openmausbot-ai"), "Should detect OpenMausBot updater & profile cache")
    try expect(ids.contains("cache-xcode-derived"), "Should detect Xcode DerivedData in dev section")
    try expect(!ids.contains("inspect-xcode-derived"), "Must NOT duplicate Xcode DerivedData in inspect section")

    // Execute cleanup on OpenMausBot candidate and verify Cookies file is 100% untouched
    if let omb = found.first(where: { $0.id == "cache-openmausbot-ai" }) {
        let outcome = CleanupExecutor.execute(candidates: [omb], homeDirectory: tmp)
        try expect(outcome.freedBytes > 0, "Should free OpenMausBot cache bytes")
        try expect(fm.fileExists(atPath: cookiesURL.path), "Bot profile Cookies file must NEVER be deleted")
    }
}

suite.test("v2.0: ProcessScanner.isNormalChromeRendererProcess isolates GUI Chrome from headless automation") {
    let normalRenderer = RawProcessInfo(
        pid: 1001, ppid: 1000, cpuPercent: 55.0, rssBytes: 200_000_000, elapsed: "01:00",
        comm: "Google Chrome Helper (Renderer)",
        args: "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer) --type=renderer"
    )
    let headlessRenderer = RawProcessInfo(
        pid: 2001, ppid: 2000, cpuPercent: 65.0, rssBytes: 200_000_000, elapsed: "01:00",
        comm: "Google Chrome Helper (Aperitif Renderer)",
        args: "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper (Aperitif Renderer).app/Contents/MacOS/Google Chrome Helper (Aperitif Renderer) --type=renderer --user-data-dir=/Users/ducdung/.openmausbot/agent-browser-profiles/c7bafa6b"
    )

    try expect(ProcessScanner.isNormalChromeRendererProcess(normalRenderer), "Normal GUI Chrome renderer must match")
    try expect(!ProcessScanner.isNormalChromeRendererProcess(headlessRenderer), "Headless automation renderer must NOT match normal Chrome renderer killer")
}

suite.test("v2.0: BrowserTabInspector.sortForSafeBatchClosing prevents index shifting") {
    let tabs = [
        BrowserTabItem(browser: "Google Chrome", windowIndex: 1, tabIndex: 2, title: "A", url: "https://a.com"),
        BrowserTabItem(browser: "Google Chrome", windowIndex: 1, tabIndex: 5, title: "B", url: "https://b.com"),
        BrowserTabItem(browser: "Google Chrome", windowIndex: 2, tabIndex: 1, title: "C", url: "https://c.com"),
        BrowserTabItem(browser: "Brave Browser", windowIndex: 1, tabIndex: 3, title: "D", url: "https://d.com")
    ]
    let sorted = BrowserTabInspector.sortForSafeBatchClosing(tabs)
    try expectEqual(sorted[0].browser, "Brave Browser")
    try expectEqual(sorted[1].windowIndex, 2)
    try expectEqual(sorted[2].windowIndex, 1)
    try expectEqual(sorted[2].tabIndex, 5)
    try expectEqual(sorted[3].tabIndex, 2)
}

suite.test("v2.0: BenchmarkRunner saves exactly 1 history entry per run and calculates composite score") {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("MacPulseBenchV2-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: tmp) }

    let runner = BenchmarkRunner(historyFileURL: tmp, diskTestBytes: 4 * 1_048_576)
    let res = try runner.runSync(localURLToProbe: nil)
    let history = runner.loadHistory()
    try expectEqual(history.count, 1)
    let score = BenchmarkRunner.compositeScore(for: res)
    try expect(score >= 1 && score <= 100, "Composite score should be between 1 and 100")
}

suite.test("v2.0: HealthAnalyzer detects stuck Chrome renderers and thermal pressure") {
    let snap = SystemSnapshot(
        cpu: CPUMetrics(userPercent: 30, systemPercent: 10, idlePercent: 60, coreCount: 8, load1m: 2.0, load5m: 2.0, load15m: 2.0),
        memory: MemoryMetrics(
            totalBytes: 16 * 1_073_741_824, activeBytes: 4 * 1_073_741_824, inactiveBytes: 2 * 1_073_741_824,
            wiredBytes: 2 * 1_073_741_824, compressedBytes: 1 * 1_073_741_824, freeBytes: 7 * 1_073_741_824,
            purgeableBytes: 0, appMemoryBytes: 3 * 1_073_741_824, cachedFilesBytes: 2 * 1_073_741_824,
            swapTotalBytes: 0, swapUsedBytes: 0, swapins: 0, swapouts: 0
        ),
        disk: DiskMetrics(totalBytes: 250_000_000_000, availableBytes: 80_000_000_000, usedBytes: 170_000_000_000),
        thermalLevel: .serious,
        uptimeSeconds: 7200
    )
    let report = HealthAnalyzer.analyze(snapshot: snap, processGroups: [], stuckChromeRendererCount: 2, stuckChromeRendererCPU: 45.0)
    try expect(report.findings.contains { $0.id == "thermal-pressure" }, "Should flag thermal pressure")
    try expect(report.findings.contains { $0.id == "stuck-chrome-renderers" && $0.recommendedAction == .killStuckChromeRenderers }, "Should flag stuck Chrome renderers with 1-click action")
    try expectEqual(snap.memory.usedBytes, 6 * 1_073_741_824) // appMemory(3G) + wired(2G) + compressed(1G)
}

suite.test("v2.0: VietnameseSettings quickTelex default consistency and precise Windows App detection") {
    let emptyJSON = Data("{}".utf8)
    let decoded = try JSONDecoder().decode(VietnameseSettings.self, from: emptyJSON)
    try expectEqual(decoded.quickTelex, VietnameseSettings().quickTelex)
    try expectEqual(decoded.quickTelex, false)

    try expect(VietnameseAppDetector.isVPSOrRemoteApp(bundleID: "com.microsoft.rdc.macos", appName: "Windows App"), "Windows App must be detected")
    try expect(!VietnameseAppDetector.isVPSOrRemoteApp(bundleID: "com.example.windowmanager", appName: "My Windows Manager"), "Generic app containing word 'windows' must NOT be misclassified as VPS")
}

suite.test("v2.0: SystemTelemetry HardwareSpecs reports valid hardware metrics") {
    let specs = SystemTelemetryReader.getHardwareSpecs()
    try expect(specs.coreCount >= 1, "Core count should be >= 1")
    try expect(specs.totalRAMGB >= 4, "Total RAM GB should be >= 4")
    try expect(!specs.compactBadge.isEmpty, "Compact badge should not be empty")
}

suite.test("v2.0: Antigravity GetUserStatus parser separates Gemini and Claude/GPT-OSS quota pools + credits") {
    let mockJSON = """
    {
      "userStatus": {
        "name": "Duc Dung",
        "email": "test@example.com",
        "userTier": { "name": "Google AI Ultra" },
        "planStatus": { "availablePromptCredits": 500, "availableFlowCredits": 100 },
        "cascadeModelConfigData": {
          "clientModelConfigs": [
            { "label": "Gemini 4 Neon (High)", "quotaInfo": { "remainingFraction": 0.85, "resetTime": "2026-11-25T10:23:02Z" } },
            { "label": "Gemini 3.8 Flash (High)", "quotaInfo": { "remainingFraction": 0.90, "resetTime": "2026-11-25T10:23:02Z" } },
            { "label": "Claude Sonnet 4.6 (Thinking)", "quotaInfo": { "remainingFraction": 1.0, "resetTime": "2026-11-25T11:08:51Z" } },
            { "label": "GPT-OSS 120B (Medium)", "quotaInfo": { "remainingFraction": 0.95, "resetTime": "2026-11-25T11:08:51Z" } }
          ]
        }
      }
    }
    """
    let parsed = AITokenMonitor.parseAntigravityUserStatus(data: Data(mockJSON.utf8))
    try expect(parsed != nil, "Should parse GetUserStatus JSON")
    try expectEqual(parsed?.planTier, "Google AI Ultra")
    try expectEqual(parsed?.promptCreditsAvailable, 500)
    try expectEqual(parsed?.flowCreditsAvailable, 100)
    try expectEqual(parsed?.quotaPools.count, 2)
    try expectEqual(parsed?.quotaPools[0].id, "agy-gemini")
    try expectEqual(Int((parsed?.quotaPools[0].quota.remainingPercent ?? 0).rounded()), 85)
    try expectEqual(parsed?.quotaPools[1].id, "agy-partner")
    try expectEqual(Int((parsed?.quotaPools[1].quota.remainingPercent ?? 0).rounded()), 95)
}

suite.test("v2.0: AutoOptimizerEngine.evaluateTrigger respects disabled, high CPU, 60m cooldown, low disk, and schedule") {
    let now = Date()
    let cfg = AutoOptimizeConfig(isEnabled: true, intervalHours: 6, staleCacheDays: 7, lowDiskTriggerGB: 30.0)

    // 1. Disabled -> nil
    var disabledCfg = cfg
    disabledCfg.isEnabled = false
    try expect(AutoOptimizerEngine.evaluateTrigger(config: disabledCfg, lastRunAt: nil, availableDiskGB: 10.0, cpuBusyPercent: 10.0, now: now) == nil, "Disabled config must return nil")

    // 2. High CPU (>= 65%) -> nil
    try expect(AutoOptimizerEngine.evaluateTrigger(config: cfg, lastRunAt: nil, availableDiskGB: 10.0, cpuBusyPercent: 72.0, now: now) == nil, "High CPU must pause auto-optimize")

    // 3. Within 60-minute cooldown -> nil even under low disk
    try expect(AutoOptimizerEngine.evaluateTrigger(config: cfg, lastRunAt: now.addingTimeInterval(-1800), availableDiskGB: 12.0, cpuBusyPercent: 15.0, now: now) == nil, "60m cooldown must prevent thrashing")

    // 4. Low disk past cooldown -> .lowDisk
    try expectEqual(AutoOptimizerEngine.evaluateTrigger(config: cfg, lastRunAt: now.addingTimeInterval(-4000), availableDiskGB: 22.0, cpuBusyPercent: 20.0, now: now), .lowDisk)

    // 5. Healthy disk before interval -> nil
    try expect(AutoOptimizerEngine.evaluateTrigger(config: cfg, lastRunAt: now.addingTimeInterval(-7200), availableDiskGB: 80.0, cpuBusyPercent: 15.0, now: now) == nil, "Healthy disk before 6h interval should return nil")

    // 6. Healthy disk past interval -> .scheduled
    try expectEqual(AutoOptimizerEngine.evaluateTrigger(config: cfg, lastRunAt: now.addingTimeInterval(-7 * 3600), availableDiskGB: 80.0, cpuBusyPercent: 15.0, now: now), .scheduled)
}

suite.test("v2.0: AutoOptimizerEngine.runPass sweeps stale caches/updaters/logs/dead tmp while protecting active files, Cookies, and Trash") {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("MacPulseAutoOptTest-\(UUID().uuidString)")
    let mockHome = root.appendingPathComponent("home", isDirectory: true)
    let mockTmp = root.appendingPathComponent("tmp", isDirectory: true)
    defer { try? fm.removeItem(at: root) }

    func setFileTimes(_ url: URL, date: Date) {
        let secs = Int(date.timeIntervalSince1970)
        var tv = [timeval(tv_sec: secs, tv_usec: 0), timeval(tv_sec: secs, tv_usec: 0)]
        utimes(url.path, &tv)
    }

    let now = Date()
    let tenDaysAgo = now.addingTimeInterval(-10 * 86400)
    let twoDaysAgo = now.addingTimeInterval(-2 * 86400)
    let twoHoursAgo = now.addingTimeInterval(-7200)
    let oneHourAgo = now.addingTimeInterval(-3600)
    let fiveMinsAgo = now.addingTimeInterval(-300)

    // 1. Stale vs Fresh browser cache
    let chromeCache = mockHome.appendingPathComponent("Library/Caches/Google/Chrome/Default/Cache")
    try fm.createDirectory(at: chromeCache, withIntermediateDirectories: true)
    let staleCacheFile = chromeCache.appendingPathComponent("stale.bin")
    let freshCacheFile = chromeCache.appendingPathComponent("fresh.bin")
    try Data(repeating: 0xAA, count: 64_000).write(to: staleCacheFile)
    try Data(repeating: 0xBB, count: 64_000).write(to: freshCacheFile)
    setFileTimes(staleCacheFile, date: tenDaysAgo)
    setFileTimes(freshCacheFile, date: oneHourAgo)

    // 2. Old ShipIt .app updater package (2 days old)
    let shipItApp = mockHome.appendingPathComponent("Library/Caches/com.google.antigravity.ShipIt/OldUpdate.app")
    let shipItContents = shipItApp.appendingPathComponent("Contents")
    try fm.createDirectory(at: shipItContents, withIntermediateDirectories: true)
    let shipItFile = shipItContents.appendingPathComponent("payload.bin")
    try Data(repeating: 0xCC, count: 50_000).write(to: shipItFile)
    setFileTimes(shipItFile, date: twoDaysAgo)
    setFileTimes(shipItApp, date: twoDaysAgo)

    // 3. Protected Chrome Cookies & User Trash (30 days old — MUST NEVER BE TOUCHED)
    let cookiesDir = mockHome.appendingPathComponent("Library/Application Support/Google/Chrome/Default")
    try fm.createDirectory(at: cookiesDir, withIntermediateDirectories: true)
    let cookiesFile = cookiesDir.appendingPathComponent("Cookies")
    try Data(repeating: 0x11, count: 8192).write(to: cookiesFile)
    setFileTimes(cookiesFile, date: now.addingTimeInterval(-30 * 86400))

    let trashDir = mockHome.appendingPathComponent(".Trash")
    try fm.createDirectory(at: trashDir, withIntermediateDirectories: true)
    let trashFile = trashDir.appendingPathComponent("keep-me.txt")
    try Data("important".utf8).write(to: trashFile)
    setFileTimes(trashFile, date: now.addingTimeInterval(-30 * 86400))

    // 4. Oversized LocalWP log (> 15 MB)
    let localLogDir = mockHome.appendingPathComponent("Local Sites/testsite/logs/php")
    try fm.createDirectory(at: localLogDir, withIntermediateDirectories: true)
    let bigLog = localLogDir.appendingPathComponent("error.log")
    try Data(repeating: 0x41, count: 16 * 1_048_576).write(to: bigLog)

    // 5. /tmp automation profiles: 1 live, 1 dead old, 1 recent
    let liveProf = mockTmp.appendingPathComponent("playwright_chromiumdev_profile-LIVE")
    let deadProf = mockTmp.appendingPathComponent("playwright_chromiumdev_profile-DEAD")
    let recentProf = mockTmp.appendingPathComponent("agent-browser-RECENT")
    for p in [liveProf, deadProf, recentProf] {
        try fm.createDirectory(at: p, withIntermediateDirectories: true)
        try Data(repeating: 0xDD, count: 32_000).write(to: p.appendingPathComponent("data.bin"))
    }
    setFileTimes(liveProf, date: twoHoursAgo)
    setFileTimes(deadProf, date: twoHoursAgo)
    setFileTimes(recentProf, date: fiveMinsAgo)

    let cfg = AutoOptimizeConfig(
        isEnabled: true,
        intervalHours: 6,
        staleCacheDays: 7,
        lowDiskTriggerGB: 30.0,
        autoCleanStaleCaches: true,
        autoCleanUpdaterGarbage: true,
        autoTruncateOversizedLogs: true,
        autoCleanOrphanTempProfiles: true
    )

    let record = AutoOptimizerEngine.runPass(
        config: cfg,
        trigger: .scheduled,
        homeDirectory: mockHome,
        tempDirectory: mockTmp,
        liveProcessArgs: ["/Applications/Google Chrome.app --user-data-dir=/tmp/playwright_chromiumdev_profile-LIVE"],
        now: now
    )

    try expect(!fm.fileExists(atPath: staleCacheFile.path), "10-day-old cache file must be deleted")
    try expect(fm.fileExists(atPath: freshCacheFile.path), "1-hour-old fresh cache file must stay intact")
    try expect(!fm.fileExists(atPath: shipItApp.path), "2-day-old ShipIt .app bundle must be removed")
    try expect(fm.fileExists(atPath: cookiesFile.path), "Chrome Cookies must NEVER be deleted")
    try expect(fm.fileExists(atPath: trashFile.path), "User Trash must NEVER be auto-deleted")

    try expect(fm.fileExists(atPath: bigLog.path), "Truncated log file must still exist")
    try expectEqual(CleanupScanner.fileSize(at: bigLog), 0)

    try expect(fm.fileExists(atPath: liveProf.path), "Active live automation /tmp profile must NOT be deleted")
    try expect(!fm.fileExists(atPath: deadProf.path), "Dead old /tmp profile must be deleted")
    try expect(fm.fileExists(atPath: recentProf.path), "Recent (<30m) /tmp profile must stay intact")

    try expectEqual(record.truncatedLogsCount, 1)
    try expectEqual(record.cleanedOrphanProfilesCount, 1)
    try expect(record.removedFilesCount >= 2, "Should have removed stale cache file + ShipIt package")
    try expect(record.freedBytes >= 16 * 1_048_576, "Freed bytes should include truncated log and stale caches")
}

suite.test("v2.0: AutoOptimizerStore persists and reloads config, lifetime freed bytes, and history") {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("MacPulseAutoOptStore-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: tmp) }

    let store = AutoOptimizerStore(fileURL: tmp)
    let rec = AutoOptimizeRunRecord(
        trigger: .lowDisk,
        freedBytes: 256_000_000,
        removedFilesCount: 42,
        truncatedLogsCount: 1,
        cleanedOrphanProfilesCount: 2,
        summary: "Giải phóng 256 MB"
    )
    let state = PersistedAutoOptimizeState(
        config: AutoOptimizeConfig(isEnabled: true, intervalHours: 12, staleCacheDays: 3, lowDiskTriggerGB: 40.0),
        lastRunAt: Date(timeIntervalSince1970: 1_700_000_000),
        totalLifetimeFreedBytes: 512_000_000,
        history: [rec]
    )
    try store.save(state)

    let reloaded = store.load()
    try expectEqual(reloaded.config.intervalHours, 12)
    try expectEqual(reloaded.config.staleCacheDays, 3)
    try expectEqual(reloaded.config.lowDiskTriggerGB, 40.0)
    try expectEqual(reloaded.totalLifetimeFreedBytes, 512_000_000)
    try expectEqual(reloaded.history.count, 1)
    try expectEqual(reloaded.history.first?.trigger, .lowDisk)
    try expectEqual(reloaded.history.first?.removedFilesCount, 42)
}

suite.test("IME 45: Fast typing circumflex after tone in Telex and VNI (tiếng, việt, bộ, về, đến, một, rồi, vẫn, thế)") {
    let eng = VietnameseEngine(settings: VietnameseSettings(inputMethod: .telex))

    // tiếng
    try expectEqual(eng.simulate("tieengs"), "tiếng")
    try expectEqual(eng.simulate("tienges"), "tiếng")
    try expectEqual(eng.simulate("tiengse"), "tiếng")
    try expectEqual(eng.simulate("tieseng"), "tiếng")
    try expectEqual(eng.simulate("tiesnge"), "tiếng")
    try expectEqual(eng.simulate("tiensge"), "tiếng")

    // việt & viết
    try expectEqual(eng.simulate("vieetj"), "việt")
    try expectEqual(eng.simulate("vietej"), "việt")
    try expectEqual(eng.simulate("vietje"), "việt")
    try expectEqual(eng.simulate("viejet"), "việt")
    try expectEqual(eng.simulate("viejte"), "việt")
    try expectEqual(eng.simulate("vietse"), "viết")
    try expectEqual(eng.simulate("vieset"), "viết")

    // bộ, về, đến, một, rồi, cần, vẫn, nhiều, muốn, xuống, thuộc
    try expectEqual(eng.simulate("bojo"), "bộ")
    try expectEqual(eng.simulate("vefe"), "về")
    try expectEqual(eng.simulate("ddense"), "đến")
    try expectEqual(eng.simulate("ddesen"), "đến")
    try expectEqual(eng.simulate("motjo"), "một")
    try expectEqual(eng.simulate("mojot"), "một")
    try expectEqual(eng.simulate("roifo"), "rồi")
    try expectEqual(eng.simulate("rofio"), "rồi")
    try expectEqual(eng.simulate("rofoi"), "rồi")
    try expectEqual(eng.simulate("canfa"), "cần")
    try expectEqual(eng.simulate("cafan"), "cần")
    try expectEqual(eng.simulate("vanxa"), "vẫn")
    try expectEqual(eng.simulate("vaxan"), "vẫn")
    try expectEqual(eng.simulate("nhieufe"), "nhiều")
    try expectEqual(eng.simulate("nhiefeu"), "nhiều")
    try expectEqual(eng.simulate("muonso"), "muốn")
    try expectEqual(eng.simulate("xuongso"), "xuống")
    try expectEqual(eng.simulate("thuocjo"), "thuộc")

    // Protect Vietnamese thế / thể / thí on Space
    try expectEqual(eng.simulate("these "), "thế ")
    try expectEqual(eng.simulate("there "), "thể ")
    try expectEqual(eng.simulate("this "), "thí ")

    // VNI tone-before-circumflex
    let vni = VietnameseEngine(settings: VietnameseSettings(inputMethod: .vni))
    try expectEqual(vni.simulate("e16"), "ế")
    try expectEqual(vni.simulate("o56"), "ộ")
    try expectEqual(vni.simulate("a26"), "ầ")
    try expectEqual(vni.simulate("viet56"), "việt")
    try expectEqual(vni.simulate("tieng16"), "tiếng")
}

suite.test("IME 46: Composing rhymes (uê, êu, ênh, uâ) + English words + accurate browser detector") {
    let eng = VietnameseEngine(settings: VietnameseSettings(inputMethod: .telex))

    // uê
    try expectEqual(eng.simulate("thuee"), "thuê")
    try expectEqual(eng.simulate("thuees"), "thuế")
    try expectEqual(eng.simulate("thuese"), "thuế")
    try expectEqual(eng.simulate("huees"), "huế")
    try expectEqual(eng.simulate("huese"), "huế")
    try expectEqual(eng.simulate("hueej"), "huệ")
    try expectEqual(eng.simulate("hueje"), "huệ")
    try expectEqual(eng.simulate("khueechs"), "khuếch")
    try expectEqual(eng.simulate("khuechse"), "khuếch")

    // êu
    try expectEqual(eng.simulate("neeus"), "nếu")
    try expectEqual(eng.simulate("neues"), "nếu")
    try expectEqual(eng.simulate("neuse"), "nếu")
    try expectEqual(eng.simulate("neseu"), "nếu")
    try expectEqual(eng.simulate("nesue"), "nếu")
    try expectEqual(eng.simulate("ddeuef"), "đều")
    try expectEqual(eng.simulate("ddeufe"), "đều")
    try expectEqual(eng.simulate("keue"), "kêu")

    // ênh
    try expectEqual(eng.simulate("beenhj"), "bệnh")
    try expectEqual(eng.simulate("benhej"), "bệnh")
    try expectEqual(eng.simulate("benhje"), "bệnh")
    try expectEqual(eng.simulate("kenhe"), "kênh")
    try expectEqual(eng.simulate("lenhej"), "lệnh")
    try expectEqual(eng.simulate("chenhe"), "chênh")

    // uâ
    try expectEqual(eng.simulate("tuaanf"), "tuần")
    try expectEqual(eng.simulate("tuanaf"), "tuần")
    try expectEqual(eng.simulate("tuanfa"), "tuần")
    try expectEqual(eng.simulate("xuana"), "xuân")
    try expectEqual(eng.simulate("thuanaj"), "thuận")
    try expectEqual(eng.simulate("thuanja"), "thuận")
    try expectEqual(eng.simulate("luataj"), "luật")
    try expectEqual(eng.simulate("xuatas"), "xuất")
    try expectEqual(eng.simulate("xuatsa"), "xuất")
    try expectEqual(eng.simulate("chuanar"), "chuẩn")

    // English words still unroll cleanly
    try expectEqual(eng.simulate("reset"), "reset")
    try expectEqual(eng.simulate("reset "), "reset ")
    try expectEqual(eng.simulate("result"), "result")
    try expectEqual(eng.simulate("result "), "result ")
    try expectEqual(eng.simulate("user"), "user")
    try expectEqual(eng.simulate("user "), "user ")
    try expectEqual(eng.simulate("use "), "use ")

    // Browser detector must not false-match "arc" inside unrelated app names
    try expect(VietnameseAppDetector.isBrowserOrSearchApp(bundleID: "company.thebrowser.Browser"), "Arc bundle must match")
    try expect(VietnameseAppDetector.isBrowserOrSearchApp(bundleID: "com.raycast.macos"), "Raycast must match")
    try expect(!VietnameseAppDetector.isBrowserOrSearchApp(bundleID: "com.apple.archiveutility", appName: "Archive Utility"), "Archive Utility must NOT match Arc browser")
}

suite.test("v2.0: OpenCodeMonitor isolates interactive TUI sessions from headless OpenMausBot/ACP bots and detects completions") {
    let monitor = OpenCodeMonitor(databaseURL: URL(fileURLWithPath: "/nonexistent/opencode.db"))
    let cfg = OpenCodeNotifyConfig(isEnabled: true, onlyInteractiveSessions: true, onlyTopLevelSessions: true, ignoreEmptyBotSessions: true, minDurationSeconds: 0)

    let t0 = Date(timeIntervalSince1970: 1_795_594_000)
    let t0Ms = Int64(t0.timeIntervalSince1970 * 1000)

    // Poll 1 (baseline):
    // - 1 historical TUI session (agent=build, time_viewed set)
    // - 1 active TUI session in plan mode (agent=plan, time_viewed set, JSON model)
    // - 1 headless OpenMausBot ACP session (agent=nil, time_viewed=nil -> MUST be ignored!)
    // - 1 child subagent session (parentID set -> MUST be ignored!)
    let initialSessions = [
        OpenCodeSessionItem(id: "ses-old", rawTitle: "Old task", directory: "/work/alonepro", agent: "build", model: "{\"id\":\"gpt-6.1-terra\",\"providerID\":\"openai\"}", timeBusyMs: t0Ms - 60_000, timeIdleMs: t0Ms - 20_000, timeViewedMs: t0Ms - 20_000, timeUpdatedMs: t0Ms - 20_000, outcome: .succeeded),
        OpenCodeSessionItem(id: "ses-active", rawTitle: "Responsive plan", directory: "/work/alonepro", agent: "plan", model: "{\"id\":\"gpt-6.1-sol\",\"providerID\":\"openai\"}", latestPrompt: "lên plan chi tiết đi", timeBusyMs: t0Ms - 10_000, timeIdleMs: t0Ms - 50_000, timeViewedMs: t0Ms - 50_000, timeUpdatedMs: t0Ms - 10_000, outcome: .succeeded),
        OpenCodeSessionItem(id: "ses-omb-bot", rawTitle: "Team task planning with OpenCode limits", directory: "/Volumes/DEVELOPER/beplus-site-assistant-pro", agent: nil, timeBusyMs: t0Ms - 8_000, timeIdleMs: nil, timeViewedMs: nil, timeUpdatedMs: t0Ms - 8_000, outcome: .unknown),
        OpenCodeSessionItem(id: "ses-child", rawTitle: "Subagent work", directory: "/work/alonepro", parentID: "ses-active", agent: "explore", timeBusyMs: t0Ms - 8_000, timeIdleMs: nil, timeViewedMs: nil, timeUpdatedMs: t0Ms - 8_000, outcome: .unknown)
    ]

    let r1 = monitor.evaluateSnapshotForTesting(sessions: initialSessions, config: cfg, now: t0)
    try expectEqual(r1.newlyCompleted.count, 0, "Baseline poll must never spam notifications for historical tasks")
    try expectEqual(r1.runningSessions.count, 1, "Only interactive TUI session must appear as running")
    try expectEqual(r1.runningSessions.first?.id, "ses-active")
    try expectEqual(r1.runningSessions.first?.displayModel, "gpt-6.1-sol")
    try expectEqual(r1.runningSessions.first?.modeBadgeLabel, "PLAN")

    // Poll 2 (+15s): ses-active finishes cleanly (duration = 25s), OpenMausBot & child also finish (must be filtered!)
    let t1 = t0.addingTimeInterval(15)
    let t1Ms = Int64(t1.timeIntervalSince1970 * 1000)
    let finishedSessions = [
        OpenCodeSessionItem(id: "ses-old", rawTitle: "Old task", directory: "/work/alonepro", agent: "build", timeBusyMs: t0Ms - 60_000, timeIdleMs: t0Ms - 20_000, timeViewedMs: t0Ms - 20_000, timeUpdatedMs: t1Ms, outcome: .succeeded),
        OpenCodeSessionItem(id: "ses-active", rawTitle: "Responsive plan", directory: "/work/alonepro", agent: "plan", latestPrompt: "lên plan chi tiết đi", timeBusyMs: t0Ms - 10_000, timeIdleMs: t1Ms, timeViewedMs: t1Ms, timeUpdatedMs: t1Ms, outcome: .succeeded),
        OpenCodeSessionItem(id: "ses-omb-bot", rawTitle: "Team task planning with OpenCode limits", directory: "/Volumes/DEVELOPER/beplus-site-assistant-pro", agent: nil, timeBusyMs: t0Ms - 8_000, timeIdleMs: t1Ms, timeViewedMs: nil, timeUpdatedMs: t1Ms, outcome: .succeeded),
        OpenCodeSessionItem(id: "ses-child", rawTitle: "Subagent work", directory: "/work/alonepro", parentID: "ses-active", agent: "explore", timeBusyMs: t0Ms - 8_000, timeIdleMs: t1Ms, timeViewedMs: nil, timeUpdatedMs: t1Ms, outcome: .succeeded)
    ]

    let r2 = monitor.evaluateSnapshotForTesting(sessions: finishedSessions, config: cfg, now: t1)
    try expectEqual(r2.runningSessions.count, 0)
    try expectEqual(r2.newlyCompleted.count, 1, "Exactly 1 completion event should fire for interactive TUI session ses-active")
    try expectEqual(r2.newlyCompleted.first?.sessionID, "ses-active")
    try expectEqual(r2.newlyCompleted.first?.projectName, "alonepro")
    try expectEqual(r2.newlyCompleted.first?.modeLabel, "PLAN")
    try expectEqual(r2.newlyCompleted.first?.promptSummary, "lên plan chi tiết đi")
    try expectEqual(r2.newlyCompleted.first?.outcome, .succeeded)
    try expect((r2.newlyCompleted.first?.durationSeconds ?? 0) >= 24.5, "Duration should be ~25s")

    // Poll 3 (+20s): ses-active gets time_updated bumped (e.g. viewed in UI) without new time_idle -> 0 duplicate alerts!
    let t2 = t0.addingTimeInterval(20)
    let t2Ms = Int64(t2.timeIntervalSince1970 * 1000)
    let viewedSessions = [
        OpenCodeSessionItem(id: "ses-active", rawTitle: "Responsive plan", directory: "/work/alonepro", agent: "plan", timeBusyMs: t0Ms - 10_000, timeIdleMs: t1Ms, timeViewedMs: t2Ms, timeUpdatedMs: t2Ms, outcome: .succeeded)
    ]
    let r3 = monitor.evaluateSnapshotForTesting(sessions: viewedSessions, config: cfg, now: t2)
    try expectEqual(r3.newlyCompleted.count, 0, "Viewing an already-completed session must NOT re-trigger notification")
}

suite.test("v2.0: OpenCodeMonitor reads real SQLite session_v2 table and skips redundant reads via stat() fingerprint") {
    let fm = FileManager.default
    let tmpDir = fm.temporaryDirectory.appendingPathComponent("MacPulseOCSQLite-\(UUID().uuidString)")
    try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmpDir) }

    let dbURL = tmpDir.appendingPathComponent("opencode.db")
    var db: OpaquePointer?
    try expectEqual(sqlite3_open(dbURL.path, &db), SQLITE_OK)
    defer { sqlite3_close(db) }

    let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
    let createSQL = """
    CREATE TABLE session_v2 (
        id TEXT PRIMARY KEY,
        parent_id TEXT,
        directory TEXT NOT NULL,
        title TEXT,
        agent TEXT,
        model TEXT,
        time_busy INTEGER,
        time_idle INTEGER,
        time_viewed INTEGER,
        idle_outcome TEXT,
        time_updated INTEGER NOT NULL
    );
    INSERT INTO session_v2 VALUES ('ses-1', NULL, '/Volumes/DEVELOPER/macpluse', 'Refactor UI', 'build', '{"id":"gpt-6.1-terra","providerID":"openai"}', \(nowMs - 8000), NULL, \(nowMs - 8000), NULL, \(nowMs - 8000));
    INSERT INTO session_v2 VALUES ('ses-bot', NULL, '/Volumes/DEVELOPER/bot-repo', 'Bot task', NULL, NULL, \(nowMs - 7000), NULL, NULL, NULL, \(nowMs - 7000));
    """
    try expectEqual(sqlite3_exec(db, createSQL, nil, nil, nil), SQLITE_OK)

    let monitor = OpenCodeMonitor(databaseURL: dbURL)
    let cfg = OpenCodeNotifyConfig(isEnabled: true, onlyInteractiveSessions: true, minDurationSeconds: 0)

    let p1 = monitor.poll(config: cfg, now: Date(timeIntervalSince1970: Double(nowMs) / 1000.0))
    try expect(p1.isDatabaseAvailable, "Mock DB must be detected")
    try expect(p1.didReadDatabase, "First poll must read SQLite")
    try expectEqual(p1.runningSessions.count, 1, "Must filter out headless bot session without time_viewed/agent")
    try expectEqual(p1.runningSessions.first?.displayTitle, "Refactor UI")
    try expectEqual(p1.runningSessions.first?.displayModel, "gpt-6.1-terra")

    // Second poll without DB change -> stat() skips SQLite read completely!
    let p2 = monitor.poll(config: cfg, now: Date(timeIntervalSince1970: Double(nowMs + 1000) / 1000.0))
    try expect(!p2.didReadDatabase, "Unchanged DB must skip SQLite read via stat() fingerprint")

    // Update DB: session completes!
    let doneMs = nowMs + 5000
    let updateSQL = "UPDATE session_v2 SET time_idle = \(doneMs), idle_outcome = 'succeeded', time_updated = \(doneMs) WHERE id = 'ses-1';"
    try expectEqual(sqlite3_exec(db, updateSQL, nil, nil, nil), SQLITE_OK)

    let p3 = monitor.poll(config: cfg, forceRead: true, now: Date(timeIntervalSince1970: Double(doneMs) / 1000.0))
    try expectEqual(p3.runningSessions.count, 0)
    try expectEqual(p3.newlyCompleted.count, 1, "SQLite busy->idle transition must trigger completion event")
    try expectEqual(p3.newlyCompleted.first?.title, "Refactor UI")
    try expectEqual(p3.newlyCompleted.first?.modeLabel, "CODE")
}

suite.test("v2.0: OpenCodeMonitorStore persists config and recent alert history") {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("MacPulseOCStore-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: tmp) }

    let store = OpenCodeMonitorStore(fileURL: tmp)
    let ev = OpenCodeCompletionEvent(
        sessionID: "ses-99",
        title: "Fix checkout flow",
        projectName: "somnia",
        directory: "/work/somnia",
        outcome: .succeeded,
        durationSeconds: 95
    )
    let state = PersistedOpenCodeNotifyState(
        config: OpenCodeNotifyConfig(isEnabled: true, playSound: true, soundName: "Hero", minDurationSeconds: 10),
        recentAlerts: [ev]
    )
    try store.save(state)

    let loaded = store.load()
    try expectEqual(loaded.config.soundName, "Hero")
    try expectEqual(loaded.config.minDurationSeconds, 10)
    try expectEqual(loaded.recentAlerts.count, 1)
    try expectEqual(loaded.recentAlerts.first?.projectName, "somnia")
}

suite.test("v2.0: AutoOptimizer 1-hour schedule, RAM pressure trigger, and work-safe idle app selection") {
    let now = Date()
    let cfg1h = AutoOptimizeConfig(
        isEnabled: true,
        intervalHours: 1,
        staleCacheDays: 1,
        lowDiskTriggerGB: 30.0,
        autoCloseIdleApps: true,
        idleAppTimeoutMinutes: 60,
        autoThrottleBackgroundHogs: true
    )

    // 1. 1-hour scheduled trigger fires at 60m (3600s) and NOT at 40m (2400s)
    try expect(AutoOptimizerEngine.evaluateTrigger(config: cfg1h, lastRunAt: now.addingTimeInterval(-2400), availableDiskGB: 80.0, cpuBusyPercent: 20.0, compressedRAMGB: 2.0, now: now) == nil, "40m should not trigger 1h schedule")
    try expectEqual(AutoOptimizerEngine.evaluateTrigger(config: cfg1h, lastRunAt: now.addingTimeInterval(-3600), availableDiskGB: 80.0, cpuBusyPercent: 20.0, compressedRAMGB: 2.0, now: now), .scheduled)

    // 2. RAM pressure trigger fires at 35m (2100s >= 30m) when compressedRAMGB >= 5.0
    try expectEqual(AutoOptimizerEngine.evaluateTrigger(config: cfg1h, lastRunAt: now.addingTimeInterval(-2100), availableDiskGB: 80.0, cpuBusyPercent: 20.0, compressedRAMGB: 5.5, now: now), .ramPressure)

    // 3. Work-safe Idle App Selection
    let apps = [
        // Protected work apps -> MUST NEVER be selected even after 3 hours idle
        TrackedGUIApp(bundleID: "com.google.Chrome", name: "Google Chrome", pid: 10, isFrontmost: false, lastActiveAt: now.addingTimeInterval(-3 * 3600), rssBytes: 900_000_000, cpuPercent: 0.2),
        TrackedGUIApp(bundleID: "dev.warp.Warp-Stable", name: "Warp", pid: 11, isFrontmost: false, lastActiveAt: now.addingTimeInterval(-3 * 3600), rssBytes: 200_000_000, cpuPercent: 0.1),
        TrackedGUIApp(bundleID: "com.getflywheel.lightning.local", name: "Local", pid: 12, isFrontmost: false, lastActiveAt: now.addingTimeInterval(-3 * 3600), rssBytes: 300_000_000, cpuPercent: 0.0),
        TrackedGUIApp(bundleID: "com.microsoft.rdc.macos", name: "Windows App", pid: 13, isFrontmost: false, lastActiveAt: now.addingTimeInterval(-3 * 3600), rssBytes: 250_000_000, cpuPercent: 0.0),
        // Non-protected app actively working (CPU 8.5%) -> MUST NOT be closed!
        TrackedGUIApp(bundleID: "com.apple.Preview", name: "Preview", pid: 14, isFrontmost: false, lastActiveAt: now.addingTimeInterval(-2 * 3600), rssBytes: 180_000_000, cpuPercent: 8.5),
        // Non-protected app frontmost -> MUST NOT be closed!
        TrackedGUIApp(bundleID: "com.apple.Notes", name: "Notes", pid: 15, isFrontmost: true, lastActiveAt: now.addingTimeInterval(-2 * 3600), rssBytes: 120_000_000, cpuPercent: 0.0),
        // Non-protected app idle only 30 mins (< 60m) -> MUST NOT be closed!
        TrackedGUIApp(bundleID: "com.apple.Music", name: "Music", pid: 16, isFrontmost: false, lastActiveAt: now.addingTimeInterval(-1800), rssBytes: 150_000_000, cpuPercent: 0.0),
        // Non-protected genuinely idle apps (> 60m, CPU < 2%) -> MUST be selected sorted by highest RAM!
        TrackedGUIApp(bundleID: "com.brave.Browser", name: "Brave Browser", pid: 17, isFrontmost: false, lastActiveAt: now.addingTimeInterval(-90 * 60), rssBytes: 420_000_000, cpuPercent: 0.3),
        TrackedGUIApp(bundleID: "com.apple.Photos", name: "Photos", pid: 18, isFrontmost: false, lastActiveAt: now.addingTimeInterval(-120 * 60), rssBytes: 210_000_000, cpuPercent: 0.0)
    ]

    let selected = AutoOptimizerEngine.selectIdleAppsToClose(runningApps: apps, config: cfg1h, now: now)
    try expectEqual(selected.count, 2)
    try expectEqual(selected[0].bundleID, "com.brave.Browser")
    try expectEqual(selected[1].bundleID, "com.apple.Photos")

    // Custom protection lock protects Brave immediately
    var customCfg = cfg1h
    customCfg.customProtectedBundleIDs = ["com.brave.Browser"]
    let afterLock = AutoOptimizerEngine.selectIdleAppsToClose(runningApps: apps, config: customCfg, now: now)
    try expectEqual(afterLock.count, 1)
    try expectEqual(afterLock[0].bundleID, "com.apple.Photos")

    // Legacy JSON decoding backwards-compatibility
    let legacyJSON = Data("{\"isEnabled\":true,\"intervalHours\":6,\"staleCacheDays\":7,\"lowDiskTriggerGB\":30}".utf8)
    let decoded = try JSONDecoder().decode(AutoOptimizeConfig.self, from: legacyJSON)
    try expectEqual(decoded.intervalHours, 6)
    try expectEqual(decoded.autoCloseIdleApps, true)
    try expectEqual(decoded.idleAppTimeoutMinutes, 60)
    try expectEqual(decoded.autoThrottleBackgroundHogs, true)
    try expectEqual(decoded.autoHealStuckReplayd, true)
}

suite.test("v2.0: Chrome Rescue detects normal Chrome GPU (excluding headless) and replayd XPC storm") {
    let normalGPU = RawProcessInfo(
        pid: 35664,
        ppid: 35654,
        cpuPercent: 10.5,
        rssBytes: 180_000_000,
        elapsed: "05:00",
        comm: "Google Chrome Helper (GPU)",
        args: "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/130/Helpers/Google Chrome Helper (GPU).app/Contents/MacOS/Google Chrome Helper (GPU) --type=gpu-process"
    )
    let headlessGPU = RawProcessInfo(
        pid: 69860,
        ppid: 69854,
        cpuPercent: 18.0,
        rssBytes: 120_000_000,
        elapsed: "01:00",
        comm: "Google Chrome Helper (GPU)",
        args: "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper (GPU) --type=gpu-process --headless --user-data-dir=/Users/ducdung/.openclaw/browser/openclaw/user-data"
    )
    let normalRenderer = RawProcessInfo(
        pid: 85969,
        ppid: 35654,
        cpuPercent: 12.5,
        rssBytes: 318 * 1_048_576,
        elapsed: "00:45",
        comm: "Google Chrome Helper (Renderer)",
        args: "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper (Renderer) --type=renderer"
    )
    let wedgedReplayd = RawProcessInfo(
        pid: 14230,
        ppid: 1,
        cpuPercent: 142.0,
        rssBytes: 42_000_000,
        elapsed: "09-07:18:42",
        comm: "replayd",
        args: "/usr/libexec/replayd"
    )

    let aperitifGPU = RawProcessInfo(
        pid: 31384,
        ppid: 35654,
        cpuPercent: 9.2,
        rssBytes: 68_000_000,
        elapsed: "07:53",
        comm: "Google Chrome Helper (Aperitif GPU)",
        args: "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/158.0.8127.88/Helpers/Google Chrome Helper (Aperitif GPU).app/Contents/MacOS/Google Chrome Helper (Aperitif GPU)"
    )

    try expect(ProcessScanner.isNormalChromeGPUProcess(normalGPU), "Normal GUI Chrome GPU must be detected")
    try expect(ProcessScanner.isNormalChromeGPUProcess(aperitifGPU), "Chrome 158 Aperitif GPU helper must be detected")
    try expect(!ProcessScanner.isNormalChromeGPUProcess(headlessGPU), "Headless OpenMausBot Chrome GPU must NOT be touched")
    try expect(!ProcessScanner.isNormalChromeGPUProcess(normalRenderer), "Renderer must not match GPU helper")
    try expect(ProcessScanner.isReplaydProcess(wedgedReplayd), "macOS /usr/libexec/replayd must be detected")

    // HealthAnalyzer surfaces actionable 1-click replayd restart + JS/DOM loop + GPU loop findings
    let snap = SystemSnapshot(
        cpu: CPUMetrics(userPercent: 52, systemPercent: 31, idlePercent: 17, coreCount: 8, load1m: 7.8, load5m: 7.5, load15m: 7.1),
        memory: MemoryMetrics(
            totalBytes: 16 * 1_073_741_824,
            activeBytes: 6 * 1_073_741_824,
            inactiveBytes: 3 * 1_073_741_824,
            wiredBytes: 2 * 1_073_741_824,
            compressedBytes: 4 * 1_073_741_824,
            freeBytes: 512 * 1_048_576,
            purgeableBytes: 0,
            swapTotalBytes: 13 * 1_073_741_824,
            swapUsedBytes: 11 * 1_073_741_824,
            swapins: 100,
            swapouts: 200
        ),
        disk: DiskMetrics(totalBytes: 245_000_000_000, availableBytes: 60_000_000_000, usedBytes: 185_000_000_000)
    )
    let groups = ProcessScanner.aggregate([wedgedReplayd, normalGPU, normalRenderer])
    let report = HealthAnalyzer.analyze(
        snapshot: snap,
        processGroups: groups,
        stuckChromeRendererCount: 1,
        stuckChromeRendererCPU: 12.5,
        chromeGPUCPU: 10.5
    )

    let replaydFinding = report.findings.first { $0.id == "replayd-storm" }
    try expect(replaydFinding != nil, "Should flag wedged replayd storm")
    try expectEqual(replaydFinding?.recommendedAction, .restartReplayd)
    try expectEqual(replaydFinding?.safetyLevel, .safeNow)
    try expectEqual(replaydFinding?.actionLabel, "Reset replayd ngay")

    let stuckTabFinding = report.findings.first { $0.id == "stuck-chrome-renderers" }
    try expect(stuckTabFinding != nil, "Should flag 12.5% JS/DOM loop tab paired with 10.5% Chrome GPU")
    try expectEqual(stuckTabFinding?.recommendedAction, .killStuckChromeRenderers)

    // Standalone high Chrome GPU (>= 18%) without stuck renderers triggers chrome-gpu-loop
    let gpuOnlyReport = HealthAnalyzer.analyze(
        snapshot: snap,
        processGroups: [],
        stuckChromeRendererCount: 0,
        stuckChromeRendererCPU: 0,
        chromeGPUCPU: 22.0
    )
    let gpuFinding = gpuOnlyReport.findings.first { $0.id == "chrome-gpu-loop" }
    try expect(gpuFinding != nil, "Should flag high standalone Chrome GPU load")
    try expectEqual(gpuFinding?.recommendedAction, .resetChromeGPU)
    try expectEqual(gpuFinding?.actionLabel, "Reset GPU Chrome")
}

suite.test("v2.0: AutoOptimizer triggers replaydStorm even when total CPU > 65% (caused by replayd)") {
    let now = Date()
    let cfg = AutoOptimizeConfig(isEnabled: true, autoHealStuckReplayd: true)

    // System CPU is 88% (above 65% normal pause), yet replayd itself is 138% CPU -> MUST trigger replaydStorm!
    let trigger = AutoOptimizerEngine.evaluateTrigger(
        config: cfg,
        lastRunAt: now.addingTimeInterval(-900), // 15 mins ago (>= 10 min cooldown)
        availableDiskGB: 80.0,
        cpuBusyPercent: 88.0,
        compressedRAMGB: 2.0,
        replaydCPUPercent: 138.0,
        now: now
    )
    try expectEqual(trigger, .replaydStorm)

    // Within 10-minute cooldown (300s) -> must NOT re-trigger repeatedly
    let cooled = AutoOptimizerEngine.evaluateTrigger(
        config: cfg,
        lastRunAt: now.addingTimeInterval(-300),
        availableDiskGB: 80.0,
        cpuBusyPercent: 88.0,
        compressedRAMGB: 2.0,
        replaydCPUPercent: 138.0,
        now: now
    )
    try expect(cooled == nil, "replaydStorm must obey 10-minute cooldown")

    // Already throttled (nice +20) -> must NOT spam-kill replayd repeatedly when clients are looping
    let alreadyMitigated = AutoOptimizerEngine.evaluateTrigger(
        config: cfg,
        lastRunAt: now.addingTimeInterval(-900),
        availableDiskGB: 80.0,
        cpuBusyPercent: 88.0,
        compressedRAMGB: 2.0,
        replaydCPUPercent: 138.0,
        replaydAlreadyThrottled: true,
        now: now
    )
    try expect(alreadyMitigated == nil, "Already reniced replayd must not be repeatedly auto-restarted")

    // Disabled autoHealStuckReplayd -> respects normal high CPU pause
    var disabledCfg = cfg
    disabledCfg.autoHealStuckReplayd = false
    let skipped = AutoOptimizerEngine.evaluateTrigger(
        config: disabledCfg,
        lastRunAt: now.addingTimeInterval(-900),
        availableDiskGB: 80.0,
        cpuBusyPercent: 88.0,
        compressedRAMGB: 2.0,
        replaydCPUPercent: 138.0,
        now: now
    )
    try expect(skipped == nil, "Disabled autoHealStuckReplayd should stay paused under high CPU")
}

suite.test("v2.0: CleanupScanner detects macOS DiagnosticReports crash logs and Bun/Cargo caches safely") {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("macpulse-diag-test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }

    let diagDir = root.appendingPathComponent("Library/Logs/DiagnosticReports")
    let bunDir = root.appendingPathComponent(".bun/install/cache")
    try FileManager.default.createDirectory(at: diagDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: bunDir, withIntermediateDirectories: true)

    let dummy = Data(repeating: 0x42, count: 120 * 1024)
    try dummy.write(to: diagDir.appendingPathComponent("Chrome-2026-11-25.ips"))
    try dummy.write(to: bunDir.appendingPathComponent("pkg.tgz"))

    let found = CleanupScanner(homeDirectory: root).scan()
    let diagItem = found.first { $0.id == "logs-diagnostic-reports" }
    let bunItem = found.first { $0.id == "cache-bun-cargo" }
    try expect(diagItem != nil, "Should detect macOS DiagnosticReports crash logs")
    try expectEqual(diagItem?.category, .logsAndTrash)
    try expectEqual(diagItem?.tier, .safeAutoClean)
    try expect(bunItem != nil, "Should detect Bun/Cargo cache")
    try expectEqual(bunItem?.category, .developerBuild)
}

suite.test("IME 47: 'của', ua/ưa/ia words, early-tone ươ words (được/nước/người/cười/rượu/đường), and unblocked trê/rôm/ủi") {
    let telexEng = VietnameseEngine(settings: VietnameseSettings(inputMethod: .telex, quickTelex: true, smartEnglishRestore: true))
    try expectEqual(telexEng.simulate("cuar "), "của ")
    try expectEqual(telexEng.simulate("cura "), "của ")
    try expectEqual(telexEng.simulate("Cuar "), "Của ")
    try expectEqual(telexEng.simulate("CUAR "), "CỦA ")
    try expectEqual(telexEng.simulate("\"cuar\" "), "\"của\" ")
    try expectEqual(telexEng.simulate("cuwar "), "cửa ")
    try expectEqual(telexEng.simulate("cuarw "), "cửa ")
    try expectEqual(telexEng.simulate("muaf luas luaj chuaf dduax "), "mùa lúa lụa chùa đũa ")
    try expectEqual(telexEng.simulate("kiaf mias ddiax nghiax "), "kìa mía đĩa nghĩa ")

    // Early-tone ươ typing orders that previously failed due to missing uơ* composing rhymes
    try expectEqual(telexEng.simulate("dduojwc "), "được ")
    try expectEqual(telexEng.simulate("ddujowc "), "được ")
    try expectEqual(telexEng.simulate("nuoswc "), "nước ")
    try expectEqual(telexEng.simulate("nusowc "), "nước ")
    try expectEqual(telexEng.simulate("truoswc "), "trước ")
    try expectEqual(telexEng.simulate("ngufowi "), "người ")
    try expectEqual(telexEng.simulate("nguofwi "), "người ")
    try expectEqual(telexEng.simulate("cuofwi "), "cười ")
    try expectEqual(telexEng.simulate("ruojwu "), "rượu ")
    try expectEqual(telexEng.simulate("dduofwng "), "đường ")

    // Real Vietnamese words no longer hijacked by smartEnglishRestore
    try expectEqual(telexEng.simulate("tree "), "trê ")
    try expectEqual(telexEng.simulate("room "), "rôm ")
    try expectEqual(telexEng.simulate("uri "), "ủi ")
    try expectEqual(telexEng.simulate("uir "), "ủi ")

    // VNI support for của & được
    let vniEng = VietnameseEngine(settings: VietnameseSettings(inputMethod: .vni))
    try expectEqual(vniEng.simulate("cua3 "), "của ")
    try expectEqual(vniEng.simulate("cu3a "), "của ")
    try expectEqual(vniEng.simulate("d9uo7c5 "), "được ")
}

suite.summaryAndExit()


