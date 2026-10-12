# DropClip Native Platform Bridges

เอกสารและไฟล์โค้ด Native เฉพาะแต่ละระบบปฏิบัติการสำหรับการเข้าถึงฟังก์ชันระดับล่างที่ไม่สามารถทำผ่าน Dart/Flutter ได้โดยตรง (ตาม ADR-001):

| โฟลเดอร์ | แพลตฟอร์ม | ภาษา | ขอบเขตหน้าที่และความรับผิดชอบหลัก |
|---|---|---|---|
| `macos/` | macOS 12+ | Swift | `NSPasteboard` changeCount Adaptive Polling, Concealed Type Detection (`org.nspasteboard.ConcealedType`), `SMAppService` |
| `windows/` | Windows 10/11 | C++ | Win32 `AddClipboardFormatListener`, `WM_CLIPBOARDUPDATE`, Windows Registry Run key |
| `android/` | Android 10+ | Kotlin | Foreground Service (`START_STICKY`), Persistent Notification, Quick Settings `TileService`, `MediaStore` |
| `ios/` | iOS 15+ | Swift | Share Sheet Action Extension (Memory Peak < 30 MB), App Group Shared Container, `WidgetKit` |
