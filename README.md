# MacPulse

<p align="center">
  <img src="Resources/AppIcon.icns" width="128" height="128" alt="MacPulse Logo" />
</p>

<p align="center">
  <strong>Trợ thủ Menu Bar toàn diện cho macOS: Giám sát tài nguyên • Dọn rác AI & Developer • Bộ gõ Tiếng Việt chuẩn EVKey/UniKey • Benchmark Apple Silicon</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B%20Sonoma%20%2F%20Sequoia-black?style=flat-square&logo=apple" alt="macOS 14+" />
  <img src="https://img.shields.io/badge/architecture-Apple%20Silicon%20%26%20Intel-blue?style=flat-square" alt="Arch" />
  <img src="https://img.shields.io/badge/language-Swift%205.10-orange?style=flat-square&logo=swift" alt="Swift" />
  <img src="https://img.shields.io/badge/dependencies-Zero%20External%20Packages-success?style=flat-square" alt="Zero Dependencies" />
  <img src="https://img.shields.io/badge/tests-50%2F50%20passed-brightgreen?style=flat-square" alt="Tests" />
  <img src="https://img.shields.io/badge/license-MIT-purple?style=flat-square" alt="License" />
</p>

---

## 🎯 Giới thiệu

**MacPulse** là ứng dụng Menu Bar gọn nhẹ, hiệu năng cao được viết 100% bằng **Swift & SwiftUI** thuần (không phụ thuộc bất kỳ thư viện bên thứ 3 nào). Ứng dụng tích hợp tất cả các tiện ích cần thiết nhất cho lập trình viên và người dùng Mac vào trong một biểu tượng duy nhất trên thanh trạng thái:

1. **Bộ gõ Tiếng Việt chuẩn EVKey / UniKey**: Gõ tiếng Việt cấp hệ thống mượt mà, không bị nuốt phím trên Zalo/Telegram/Chrome, hỗ trợ gõ tắt (Macro) và phím tắt ngoặc vuông nhanh.
2. **Dọn dẹp hệ thống & Rác AI (AI Garbage Cleaner)**: Tự động phát hiện và dọn sạch hàng GB cache/logs từ Cursor AI, Codex, Claude, Gemini, Xcode, npm, Homebrew.
3. **Giám sát sức khỏe & Tiến trình**: Đánh giá độ nén RAM, tràn Swap, cảnh báo ổ SSD, phát hiện Chrome automation chạy ngầm (`puppeteer/playwright`) hoặc tiến trình ngốn CPU (`replayd`).
4. **Cứu hộ Chrome 1-Click**: Tắt sạch tiến trình treo, gỡ SingletonLock, dọn Shader/Service Worker cache mà vẫn giữ nguyên 100% tài khoản và bookmark.
5. **Benchmark thực tế Apple Silicon**: Đo đạc tốc độ CPU, băng thông RAM, tốc độ đọc/ghi SSD và độ trễ máy chủ WordPress cục bộ.

---

## ✨ Tính năng nổi bật

### 1. ⌨️ Bộ gõ Tiếng Việt (Native IME)
* **Chuẩn EVKey & UniKey**: Hỗ trợ 2 kiểu gõ phổ biến nhất: **Telex** và **VNI** (kèm chế độ kết hợp **Telex + VNI**).
* **Bỏ dấu tự do (Free Mark)**: Cho phép bỏ dấu ở cuối từ (`thichs` $\rightarrow$ `thích`, `chats` $\rightarrow$ `chát`) hoặc ngay sau nguyên âm (`thisch` $\rightarrow$ `thích`).
* **Hỗ trợ gõ nhanh chuẩn EVKey**:
  * Phím `w` sau phụ âm tự động tạo `ư`: `chws` $\rightarrow$ `chứ`, `chwa` $\rightarrow$ `chưa`, `nhw` $\rightarrow$ `như`, `tws` $\rightarrow$ `tứ`, `ddwngs` $\rightarrow$ `đứng`. Nhấn `ww` để hoàn tác về `w`.
  * Phím tắt ngoặc vuông: `[` $\rightarrow$ `ơ`, `]` $\rightarrow$ `ư`, `{` $\rightarrow$ `Ơ`, `}` $\rightarrow$ `Ư`, `u[` $\rightarrow$ `ươ`. Nhấn 2 lần `[[` hoặc `]]` để gõ ngoặc vuông gốc.
* **Chống nuốt phím & dính chữ trên ứng dụng Chat**: Tích hợp thuật toán đệm nhịp thông minh (settle pause), gõ cực mượt trên Zalo, Telegram, Messenger, Slack, Discord, Chrome, Safari.
* **Gõ tắt / Viết tắt (Macro Expansion)**: Mở rộng từ gõ tắt khi nhấn phím Space (`vn` $\rightarrow$ `Việt Nam`, `VN` $\rightarrow$ `VIỆT NAM`). Bảo vệ an toàn các đường dẫn web (`.vn/`) và code không bị thay thế nhầm.
* **Phím tắt chuyển đổi nhanh**: Hỗ trợ `Ctrl + Shift`, `Cmd + Shift`, `Option + Z` hoặc `Ctrl + Space` kèm âm thanh phản hồi xúc giác nhẹ.
* **Khung gõ thử (Scratchpad)**: Tích hợp sẵn bộ đếm số từ và số ký tự để kiểm tra độ nhạy trước khi gõ.

### 2. 🧹 Phân hệ Dọn dẹp (System & AI Cleaner)
* **Dọn rác AI (`.aiGarbage`)**: Quét sâu các thư mục tốn dung lượng của các công cụ AI:
  * **Cursor AI**: `CachedData`, `CachedExtensionVSIXs`, `GPUCache`, `logs`, `.cursor/ai-tracking`.
  * **Codex AI**: `.codex/cache`, `.codex/tmp`, `.cache/codex-runtimes`.
  * **Claude Desktop**: `com.anthropic.claudedesktop*`, `.claude/cache`, `.claude/logs`.
  * **Gemini & Antigravity**: `.cache/opencode*`, `.gemini/logs`.
  * **Mô hình AI cục bộ**: Checkpoints đệm từ HuggingFace (`~/.cache/huggingface`), Whisper, PyTorch.
* **Dọn rác Lập trình (`.developerBuild`)**:
  * Xcode DerivedData & Archives cũ.
  * Homebrew bottle cache, npm/yarn cache (`~/.npm/_cacache`), pip cache.
* **Phân loại độ an toàn minh bạch**:
  * `An toàn 100%`: Tệp đệm tạm, hệ thống tự tái tạo khi cần, không mất mật khẩu/tài khoản.
  * `Tự chọn`: Thùng rác, file log lớn.
  * `Chỉ kiểm tra`: Các file database hoặc thư mục nặng cần người dùng xác nhận.
* **Thao tác 1 chạm**: Nút **"Chọn tất cả an toàn"** và **"Dọn ngay"** với thanh tiến trình trực quan.

### 3. 📊 Giám sát & Quản lý tiến trình (Dashboard)
* **Tự động nhận diện phần cứng**: Nhận biết chính xác dòng máy (ví dụ `Mac mini M2 • Apple M2`).
* **Huy hiệu sức khỏe (Health Score /100)**: Tổng hợp tải CPU, độ nén RAM, áp lực Swap và dung lượng SSD khả dụng.
* **Thẻ cảnh báo nền trắng tương phản cao**: Hiển thị rõ nét, không bị chói hay xuyên thấu qua cửa sổ khác.
* **Bộ lọc tiến trình thông minh**: Tìm kiếm nhanh theo tên/PID, lọc theo nhóm (`AI / Dev`, `Trình duyệt`, `Đồ họa`, `Tiến trình nền`).

### 4. ⏱️ Đo hiệu năng thực tế (Benchmark)
* Đo tốc độ tính toán số nguyên & số thực CPU Single-Core & Multi-Core.
* Đo băng thông RAM thực tế (GB/s).
* Kiểm tra tốc độ đọc/ghi SSD tuần tự bằng file đệm tạm thời (tự động dọn sau khi đo).
* Đo độ trễ phản hồi máy chủ Local WordPress (ms).

---

## 📥 Tải về & Cài đặt (Download)

### Cách 1: Tải bản đóng gói sẵn (Khuyên dùng)
Truy cập trang [**GitHub Releases**](https://github.com/ducdung196qtr/macpulse/releases) để tải phiên bản mới nhất:
* Tải file **`MacPulse-v1.1.0-macOS.dmg`**.
* Mở file `.dmg` và kéo biểu tượng **MacPulse** vào thư mục **Applications**.
* Mở ứng dụng từ thư mục Applications.

> [!IMPORTANT]
> **Cấp quyền Trợ năng (Accessibility) để gõ Tiếng Việt:**
> Để MacPulse có thể lắng nghe phím và gõ tiếng Việt trong toàn bộ ứng dụng (Chrome, VS Code, Zalo,...):
> 1. Mở **Cài đặt hệ thống (System Settings)** $\rightarrow$ **Quyền riêng tư & Bảo mật (Privacy & Security)**.
> 2. Chọn mục **Trợ năng (Accessibility)**.
> 3. Bật công tắc cho **MacPulse**.

### Tự động khởi động cùng máy (Launch at Login):
MacPulse tự động đăng ký vào danh sách **Login Items** của macOS, luôn sẵn sàng phục vụ bạn ngay khi mở máy.

---

## 🛠️ Hướng dẫn Phát triển & Thêm tính năng (Developer Guide)

MacPulse được cấu trúc theo mô hình phân tầng chặt chẽ: tầng Core độc lập với AppKit/UI để phục vụ viết Unit Test tự động cực nhanh.

### Cấu trúc thư mục

```text
macpulse/
├── Package.swift                    # Khai báo Swift Package & các Target
├── Resources/
│   ├── AppIcon.icns                 # Biểu tượng ứng dụng chuẩn macOS
│   └── Info.plist                   # Cấu hình Bundle, LSUIElement (Menu Bar App)
├── Sources/
│   ├── MacPulseCore/                # [Core Engine] Logic thuần, không phụ thuộc UI
│   │   ├── Models.swift             # Các struct dữ liệu, Enum phân loại rác & tiến trình
│   │   ├── VietnameseEngine.swift   # Bộ gõ Telex/VNI, xử lý âm tiết & macro
│   │   ├── CleanupScanner.swift     # Quét rác AI, cache trình duyệt, dev build
│   │   ├── CleanupExecutor.swift    # Thực thi xoá tệp, giải phóng lock, kill tiến trình
│   │   ├── SystemTelemetry.swift    # Đọc CPU, RAM (sysctl/mach), SSD & Hardware Model
│   │   ├── ProcessScanner.swift     # Đọc tiến trình sống qua Darwin libproc
│   │   ├── HealthAnalyzer.swift     # Tính toán điểm sức khỏe (/100) & cảnh báo
│   │   └── BenchmarkRunner.swift    # Thuật toán đo CPU, RAM, SSD thực tế
│   └── MacPulseApp/                 # [UI & System Services] SwiftUI & AppKit
│       ├── MacPulseApp.swift        # Entry point MenuBarExtra, Popover window & TabBar
│       ├── AppViewModel.swift       # Quản lý trạng thái ứng dụng, ObservableObject
│       ├── MacInputTapService.swift # Dịch vụ CGEvent.tapCreate bắt phím cấp hệ thống
│       ├── Views/
│       │   ├── DashboardView.swift  # Giao diện tổng quan CPU/RAM/SSD & tiến trình
│       │   ├── CleanerView.swift    # Giao diện dọn rác AI, trình duyệt & RAM
│       │   ├── VietnameseView.swift # Cài đặt bộ gõ tiếng Việt, phím tắt & macro
│       │   └── BenchmarkView.swift  # Giao diện đo hiệu năng máy
│       └── ProcessRowComponents.swift
├── Tests/
│   └── MacPulseTests/
│       └── main.swift               # 50 unit tests độc lập không cần XCTest
└── scripts/
    ├── build_app.sh                 # Script biên dịch Release, ký ad-hoc và cài đặt
    ├── make_dmg.sh                  # Script đóng gói file .dmg và .zip phát hành
    └── make_icon.swift              # Script tạo bộ iconset từ vector
```

---

### Các lệnh phát triển thường dùng

#### 1. Chạy toàn bộ Unit Tests
Bộ test của MacPulse chạy hoàn toàn độc lập và không phụ thuộc Xcode IDE:
```bash
swift run MacPulseTests
```
*Kết quả mẫu: 50 passed, 0 failed.*

#### 2. Biên dịch & Cài đặt vào `/Applications/MacPulse.app`
Chạy script tự động chạy test, build bản Release tối ưu, đóng gói bundle và ký số ad-hoc:
```bash
./scripts/build_app.sh
```

#### 3. Đóng gói file `.dmg` và `.zip` để chia sẻ
```bash
./scripts/make_dmg.sh
```
File đóng gói sẽ được xuất vào thư mục `dist/` (`MacPulse-v1.1.0-macOS.dmg` dung lượng chỉ ~2.0 MB).

---

### Hướng dẫn mở rộng mã nguồn

#### 1. Thêm đường dẫn quét dọn rác mới
Mở [Sources/MacPulseCore/CleanupScanner.swift](file:///Volumes/DEVELOPER/macpluse/Sources/MacPulseCore/CleanupScanner.swift):
* Thêm đường dẫn vào mảng `scanPatterns`.
* Chỉ định danh mục tương ứng: `.aiGarbage`, `.developerBuild`, `.cache`, hoặc `.logsAndTrash`.
* Ví dụ thêm cache của một IDE mới:
  ```swift
  let myAppCache = home.appendingPathComponent("Library/Caches/com.myapp.id")
  if let item = inspectDirectory(url: myAppCache, id: "cache-myapp", title: "MyApp Cache", category: .developerBuild) {
      results.append(item)
  }
  ```

#### 2. Thêm từ gõ tắt (Macro) mặc định
Mở [Sources/MacPulseCore/VietnameseEngine.swift](file:///Volumes/DEVELOPER/macpluse/Sources/MacPulseCore/VietnameseEngine.swift):
* Chỉnh sửa bảng từ điển `VietnameseSettings.defaultMacroTable`:
  ```swift
  public static let defaultMacroTable: [String: String] = [
      "vn": "Việt Nam",
      "hcm": "Hồ Chí Minh",
      "dc": "được",
      // Thêm từ viết tắt của bạn tại đây
  ]
  ```

#### 3. Bổ sung luật chính tả hoặc vần tiếng Việt mới
Trong `VietnameseEngine.swift`:
* `validRhymes`: Tập hợp tất cả các vần tiếng Việt chuẩn khi kết thúc từ.
* `composingOnlyRhymes`: Các vần trung gian cho phép tồn tại khi người dùng đang gõ dở (ví dụ `ic` trước khi gõ thành `ich`).

---

## 📄 Bản quyền (License)

Dự án được phân phối dưới giấy phép **MIT License**. Bạn hoàn toàn có thể tự do sử dụng, chỉnh sửa và đóng góp cho cộng đồng!
