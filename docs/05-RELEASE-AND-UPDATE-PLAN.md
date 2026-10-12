# DropClip — Release, Distribution & Lifecycle Update Plan

| รายการ | รายละเอียด |
|---|---|
| **รหัสเอกสาร** | RELEASE-DC-V1.0 |
| **Document Version** | 1.0 — Realigned to SRS-DC-V1.2 & PROTO-DC-V2.0 |
| **สถานะ** | Approved Release Management Baseline |
| **Release Manager & Lead** | นายธนกฤต บุญญาวรกุล (เจ) — Team Lead & Architect |
| **Mobile Release Engineer** | นายเกื้ออนันต์ พวงนิลน้อย (เกื้อ) — Mobile Client Developer |
| **QA & Verification Lead** | นายปรมินทร์ มุขอาษา (ตามด) — QA & Performance Engineer |

---

## 1. Release Strategy & Versioning Scheme

DropClip ปฏิบัติตามมาตรฐาน **Semantic Versioning 2.0.0 (`MAJOR.MINOR.PATCH`)**:

- **MAJOR (vX.0.0):** การเปลี่ยนแปลงที่เข้ากันไม่ได้ในระดับโปรโตคอลการสื่อสาร (Breaking Protocol Changes) เช่น การเปลี่ยนรูปแบบ Wire Envelope หรือกลไก mTLS ที่ต้องจับคู่ใหม่
- **MINOR (v1.X.0):** การเพิ่มฟีเจอร์ใหม่ที่ยังคงเข้ากันได้กับโปรโตคอลเดิม (Backward-Compatible Feature Additions) เช่น การรองรับชนิดไฟล์ใหม่, การปรับปรุง UI, การเพิ่ม Widget
- **PATCH (v1.0.X):** การแก้ไขข้อผิดพลาดหรือปรับปรุงประสิทธิภาพที่ไม่มีผลต่อสัญญาระดับ API หรือ Wire Protocol (Backward-Compatible Bug Fixes)

---

## 2. Cluster Compatibility & Mixed-Version Protocol Negotiation

เนื่องจาก DropClip ทำงานแบบ Peer-to-Peer กระจายศูนย์ (Decentralized Mesh) โดยไม่มีเซิร์ฟเวอร์กลางคอยบังคับการอัปเดตพร้อมกัน อุปกรณ์ในวง LAN จึงอาจมีเวอร์ชันของซอฟต์แวร์ไม่ตรงกันในช่วงเปลี่ยนผ่าน (Mixed-Version Cluster):

### 2.1 Negotiation Flow via Control Plane (`hello` message)

เมื่ออุปกรณ์เปิดการเชื่อมต่อ WebSocket over mTLS:
1. ทั้งสองฝั่งส่งข้อความ `hello` ระบุ:
   - `v`: Protocol Wire Version ปัจจุบันของตน (เช่น `2`)
   - `min_supported_v`: Protocol Version ต่ำสุดที่ยังรองรับได้ (เช่น `1`)
   - `app_version`: รหัสเวอร์ชันของแอปพลิเคชัน (เช่น `"1.2.0"`)
2. กฎการตกลงเวอร์ชัน (Version Agreement Rules):
   - หาก $\text{Peer.v} \ge \text{Local.min\_supported\_v}$ และ $\text{Local.v} \ge \text{Peer.min\_supported\_v}$ → การสื่อสารดำเนินต่อไปได้ โดยใช้โปรโตคอลเวอร์ชันต่ำกว่าในคู่นั้น
   - หากไม่ตรงกัน → ปิด Socket ด้วยรหัส `4003` พร้อมข้อความแจ้งเตือน `E_UNSUPPORTED_VERSION`
3. Forward Compatibility Rule:
   - เมื่อโหนดได้รับ JSON Envelope ที่มี Field ที่ตนไม่รู้จัก (Unknown Fields) → **MUST ละเว้น Field นั้นอย่างปลอดภัยโดยไม่โยนข้อยกเว้น (Gracefully Ignore)**

---

## 3. Multi-Platform Packaging & Distribution Pipeline

```mermaid
flowchart TD
    Build["GitHub Actions CI Build Matrix\n(Melos Monorepo)"]
    
    subgraph macOS_Release["macOS Distribution (Intel / Apple Silicon)"]
        MacApp["DropClip.app Universal Binary"]
        MacSign["Developer ID Application Signing\nHardened Runtime"]
        MacNotarize["Apple Notary Service (notarytool)\nStapled Ticket"]
        MacDMG["Signed .dmg & Sparkle AppCast Feed"]
    end

    subgraph Windows_Release["Windows Distribution (x64 / ARM64)"]
        WinExe["DropClip.exe & MSIX Installer"]
        WinSign["Microsoft Authenticode Signing\n(Azure Trusted Signing)"]
        WinSparkle["WinSparkle AppCast Feed & Winget"]
    end

    subgraph Android_Release["Android Distribution (API 29+)"]
        AAB["Android App Bundle (.aab)"]
        PlaySign["Google Play App Signing"]
        PlayTrack["Internal -> Closed Beta -> Production"]
    end

    subgraph iOS_Release["iOS Distribution (iOS 15+)"]
        IPA["DropClip.ipa Archive"]
        AppleSign["Apple Distribution Certificate"]
        TestFlight["TestFlight Beta -> App Store Review"]
    end

    Build --> MacApp --> MacSign --> MacNotarize --> MacDMG
    Build --> WinExe --> WinSign --> WinSparkle
    Build --> AAB --> PlaySign --> PlayTrack
    Build --> IPA --> AppleSign --> TestFlight
```

### 3.1 macOS Platform Deployment
- **Packaging:** Standalone Universal 2 Binary (arm64 + x86_64) บรรจุใน `.dmg`
- **Security Entitlements:**
  - `com.apple.security.network.server` (Local Port Binding)
  - `com.apple.security.network.client` (Outbound Transport)
  - `com.apple.security.application-groups` (`$(TeamID).com.dropclip.shared`)
- **Code Signing & Notarization:** ลงนามด้วย Apple Developer ID Application พร้อมแนบ Timestamp จาก Apple Timestamp Server และทำ Notarization ผ่าน `xcrun notarytool`
- **Auto-Update:** ขับเคลื่อนด้วย **Sparkle Framework 2.x** ผ่าน HTTPS AppCast XML Feed พร้อมการตรวจสอบลายเซ็น Ed25519 ของไฟล์อัปเดต

### 3.2 Windows Platform Deployment
- **Packaging:** Windows MSIX Package และ Standalone NSIS Executable Installer
- **Code Signing:** ลงนามด้วย Microsoft Authenticode Certificate เพื่อป้องกันคำเตือน Windows SmartScreen Block
- **Auto-Update:** ขับเคลื่อนด้วย **WinSparkle** หรือการเผยแพร่ผ่าน Windows Package Manager (`winget install DropClip`)

### 3.3 Android Platform Deployment
- **Packaging:** Android App Bundle (`.aab`) พร้อม ProGuard/R8 Obfuscation
- **Permissions:**
  - `POST_NOTIFICATIONS` (Android 13+)
  - `FOREGROUND_SERVICE` พร้อม `FOREGROUND_SERVICE_CONNECTED_DEVICE` (Android 14+)
  - `ACCESS_WIFI_STATE` & `CHANGE_WIFI_MULTICAST_STATE` (mDNS Multicast Lock)
- **Deployment Track:** เผยแพร่ผ่าน Google Play Console (Internal Testing 20 เครื่อง → Closed Testing → Production)

### 3.4 iOS Platform Deployment
- **Packaging:** iOS App Archive (`.ipa`) ควบคู่กับ Share Extension Target
- **App Groups:** `group.com.dropclip.shared`
- **Deployment Track:** เผยแพร่ผ่าน Apple TestFlight สำหรับ Dogfooding และยื่นขออนุมัติผ่าน Apple App Store Review

---

## 4. Rollback Strategy & Emergency Triage Procedure

ในกรณีที่พบข้อผิดพลาดร้ายแรง (Critical Defect) ภายหลังการเผยแพร่เวอร์ชันใหม่ (เช่น บั๊กหน่วยความจำรั่ว, การซิงก์ข้อมูลขัดข้อง, หรือช่องโหว่ความปลอดภัย):

### 4.1 Triage Severity Levels
- **P0 — Emergency Blocker:** ปัญหาด้านความปลอดภัย, ข้อมูลสูญหาย, หรือแอป Crash ต่อเนื่องเมื่อเปิดใช้งาน
  - *Response Time:* ต้องออก Hotfix ภายใน **< 24 ชั่วโมง**
- **P1 — High Priority:** ฟังก์ชันหลักใช้งานไม่ได้ (เช่น mDNS หาเครื่องไม่เจอ, ส่งไฟล์ขนาดใหญ่ไม่ผ่าน)
  - *Response Time:* ต้องออก Patch ภายใน **< 72 ชั่วโมง**

### 4.2 Desktop Rollback (macOS / Windows)
- ปรับปรุง AppCast XML Feed บน GitHub Releases ให้ชี้กลับไปยังเวอร์ชันก่อนหน้าที่มีความเสถียร (Previous Stable Release) พร้อมตั้งค่า `sparkle:criticalUpdate="true"`
- ผู้ใช้ที่เปิดโปรแกรมจะได้รับการแจ้งเตือนให้อัปเดต/ถอยเวอร์ชันทันที

### 4.3 Mobile Rollback (Android / iOS)
- **Android:** ปรับลดสัดส่วน Staged Rollout บน Google Play Console ให้เหลือ 0% ทันที และเปิดเผยแพร่แพตช์ตัวใหม่ที่มี Version Code สูงกว่าเดิม
- **iOS:** ยื่นคำขอ **Expedited Review** กับ Apple App Review Team เพื่อขอปล่อยแพตช์แก้ไขฉุกเฉินภายใน 24 ชั่วโมง

### 4.4 Data Preservation Guarantee
- การอัปเดตหรือถอยเวอร์ชัน **ต้องไม่ลบฐานข้อมูล Trusted Device Store (`trusted_devices.json.enc`) หรือกุญแจใน Hardware Keystore** เด็ดขาด ผู้ใช้ไม่ต้องจับคู่อุปกรณ์ใหม่หลังการอัปเดต

---

## 5. Regulatory, Privacy & Store Compliance

### 5.1 Thailand PDPA & International Privacy Standards
- **Zero-Cloud Architecture:** DropClip ไม่มีฐานข้อมูลคลาวด์ ไม่มีการจัดเก็บข้อมูลส่วนบุคคล (PII) ของผู้ใช้นอกอุปกรณ์ของตนเอง
- **100% On-Device Processing:** ข้อมูลคลิปบอร์ดและไฟล์เดินทางผ่านเครือข่าย Wi-Fi ท้องถิ่นระหว่างอุปกรณ์ที่จับคู่เท่านั้น
- **Telemetry Anonymization:** ระบบไม่ส่งข้อมูลการใช้งานภายนอก (No Telemetry / No Analytics SDKs)

### 5.2 Apple App Store Guidelines Alignment
- **Local Network Usage:** ระบุ `NSLocalNetworkUsageDescription` ชัดเจนใน `Info.plist`:
  > "DropClip uses your local network to discover and securely synchronize clipboards and files with your paired devices."
- **Bonjour Services:** ประกาศ `_dropclip._tcp` ใน `NSBonjourServices`
- **Data Privacy Nutrition Labels:** ประกาศว่า "Data Not Collected" สำหรับทุกหมวดหมู่ข้อมูล

### 5.3 Google Play Store Policy Alignment
- **Foreground Service Policy:** ชี้แจงการใช้งาน Foreground Service ชนิด `connectedDevice` ต่อ Google Play Team ว่ามีความจำเป็นอย่างยิ่งสำหรับการรักษาการเชื่อมต่อ Socket สองทิศทางกับอุปกรณ์ที่จับคู่ในวง LAN เพื่อการรับส่งข้อมูลคลิปบอร์ดแบบเรียลไทม์
- **Scoped Storage:** ปฏิบัติตามมาตรฐาน Scoped Storage (บันทึกรูปภาพ/วิดีโอผ่าน `MediaStore` และเอกสารลง Downloads) โดยไม่ต้องขอสิทธิ์อันตราย `MANAGE_EXTERNAL_STORAGE`

---

## 6. Software Bill of Materials (SBOM) & Supply Chain Security

เพื่อความปลอดภัยสูงสุดในกระบวนการผลิตซอฟต์แวร์ (Supply Chain Security):
1. **Dependency Locking:** ตรวจสอบและบันทึก Checksum ของทุก Package ใน `pubspec.lock`, `Podfile.lock`, และ Gradle Wrapper
2. **Automated Vulnerability Audit:** รันคำสั่ง `dart pub audit` และ GitHub Dependabot ทุกสัปดาห์
3. **CycloneDX SBOM Generation:** ทุก Release Build ใน GitHub Actions จะส่งออกไฟล์ `sbom-dropclip.json` ตามมาตรฐาน CycloneDX 1.5 เพื่อให้ผู้ใช้งานและองค์กรสามารถตรวจสอบส่วนประกอบซอฟต์แวร์แบบโอเพนซอร์สได้อย่างโปร่งใส

