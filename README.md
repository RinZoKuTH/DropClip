# DropClip

> **DropClip: A Desktop-First Peer-to-Peer Clipboard Continuity and High-Throughput File Transfer System for Heterogeneous Personal Device Clusters**  
> *ดรอปคลิป: ระบบเชื่อมต่อคลิปบอร์ดและถ่ายโอนไฟล์ความเร็วสูงแบบ Peer-to-Peer บนเครือข่ายท้องถิ่น สำหรับคลัสเตอร์อุปกรณ์ส่วนบุคคลแบบข้ามแพลตฟอร์ม*

---

## 1. Overview & Capability Tiers

DropClip คือสะพานเชื่อมความต่อเนื่องของอุปกรณ์ส่วนบุคคล (Personal Device Continuity Bridge) ทำงานบนเครือข่ายท้องถิ่น (LAN / Wi-Fi) แบบ **Peer-to-Peer (P2P) 100% ไร้เซิร์ฟเวอร์กลาง (Serverless & Cloudless)** ไม่ต้องพึ่งพาอินเทอร์เน็ต และไม่ต้องสร้างบัญชีผู้ใช้ โดยออกแบบภายใต้หลักการความซื่อสัตย์ต่อข้อจำกัดของระบบปฏิบัติการ (Platform-Constrained Honesty):

| ระดับ (Tier) | แพลตฟอร์ม | Clipboard Sync Mode | ขีดความสามารถด้านการถ่ายโอนไฟล์ (File Transfer) |
|---|---|---|---|
| **Tier 1 — Full Passive** | **macOS 12+**<br>**Windows 10/11** | **อัตโนมัติเต็มรูปแบบ (Zero-Interaction)** สองทิศทางในเบื้องหลัง (p95 < 1,000 ms) | เต็มรูปแบบ (Streaming 1 MiB chunk over TLS 1.3, Fixed RAM < 100 MB, Resumable) |
| **Tier 2 — Assisted** | **Android 10+** (API 29+) | **Desktop → Android:** เขียนคลิปบอร์ดอัตโนมัติ (Foreground Service)<br>**Android → Desktop:** สั่งส่งผ่าน Quick Settings Tile หรือ Notification (1-Click) | เต็มรูปแบบ (MediaStore & Scoped Storage integration) |
| **Tier 3 — Manual-Assist** | **iOS 15+** | สั่งส่งผ่าน Share Sheet Extension, Action Button, Widgets หรือ Apple Shortcuts | เต็มรูปแบบขณะแอป Active (PhotoKit add-only & Sandboxed Files) |

---

## 2. โครงสร้าง Monorepo Workspace (ADR-005)

โปรเจกต์ได้รับการจัดโครงสร้างเป็น Monorepo โดยใช้ **Melos** บริหารจัดการแพ็กเกจ:

```
DropClip/
├── docs/                                  # เอกสารข้อกำหนดและสถาปัตยกรรมโครงการ
│   ├── 00-PROJECT-PROPOSAL-AND-PLAYBOOK.md # Proposal และ Engineering Playbook (v2.0)
│   ├── 01-PROTOCOL-SPEC.md                 # ข้อกำหนด Wire Protocol Spec ฉบับสมบูรณ์ (v2.0)
│   ├── 02-TICKETS.md                       # รายการ Task Tickets, DoR/DoD และตาราง RTM (v2.0)
│   └── 03-SRS.md                           # ข้อกำหนดความต้องการซอฟต์แวร์ (SRS-DC-V1.2)
│
├── packages/                              # โมดูล Core Libraries ที่แชร์ร่วมกัน
│   ├── dropclip_protocol/                 # Message Envelopes, SAS Calculator, Path Sanitizer
│   ├── dropclip_core/                     # Transport, TLS 1.3 Pinning, Discovery, Keystore
│   ├── dropclip_clipboard/                # Cross-OS Normalizer, Native Event Channels
│   ├── dropclip_transfer/                 # Streaming File Transfer Engine, Resumable Engine
│   └── dropclip_ui/                       # Design System Widgets, Theme Tokens
│
├── apps/                                  # แอปพลิเคชันปลายทาง
│   ├── desktop/                           # Desktop Client สำหรับ macOS และ Windows
│   └── mobile/                            # Mobile Client สำหรับ Android และ iOS
│
├── native/                                # Native Bridge Code เฉพาะแพลตฟอร์ม
│   ├── macos/                             # Swift ClipboardWatcher (Adaptive Polling)
│   ├── windows/                           # C++ ClipboardWatcher (Win32 Event-Driven)
│   ├── android/                           # Kotlin Foreground Service & Quick Settings Tile
│   └── ios/                               # Swift Share Sheet Extension (< 30 MB RAM)
│
├── tools/                                 # เครื่องมือสนับสนุนและทดสอบระบบ
│   ├── protocol_fuzzer/                   # Fuzzer ทดสอบความแข็งแกร่งของ Protocol Parser
│   └── bench/                             # Automated Performance & Latency Benchmark Suite
│
├── .github/                               # CI/CD Workflows และ Issue/PR Templates
├── melos.yaml                             # การกำหนดค่า Melos Monorepo
└── analysis_options.yaml                  # กฎการตรวจสอบคุณภาพโค้ดระดับเข้มงวด
```

---

## 3. ทีมพัฒนาและความรับผิดชอบ (Team Roles)

| ลำดับ | สมาชิกในทีม | Role Code | หน้าที่รับผิดชอบหลัก (Primary Responsibilities) |
|:---:|---|:---:|---|
| **1** | **นายธนกฤต บุญญาวรกุล (เจ)** | `LEAD` | Team Lead, Protocol Architecture, Security Engine, Native Hooks, Code Signing |
| **2** | **นายณัฐธีร์ อโณทัยไพบูลย์ (ธีร์)** | `DESK` | Desktop Discovery, Tier 1 Clipboard Sync Engine, Desktop UI & System Tray |
| **3** | **นายเกื้ออนันต์ พวงนิลน้อย (เกื้อ)** | `MOB` | Mobile Architecture, Android Tier 2 Engine, iOS Tier 3 Extension & Widgets |
| **4** | **นายปัณณ์ ศรีเจริญชัยกุล (ปัน)** | `NET` | TLS Transport, Control Plane WebSocket, Image Normalizer, Streaming File Engine |
| **5** | **นายปรมินทร์ มุขอาษา (ตามด)** | `QA` | Test Cluster Harness, Benchmark Automation, Pentest Auditing, Usability Study |

---

## 4. เริ่มต้นการพัฒนา (Quickstart)

### 4.1 ข้อกำหนดเบื้องต้น
- [Flutter SDK](https://flutter.dev) (v3.16.0 หรือใหม่กว่า) / [Dart SDK](https://dart.dev) (v3.2.0 หรือใหม่กว่า)
- [Melos](https://melos.invertase.dev) (`dart pub global activate melos`)

### 4.2 การติดตั้งและรันชุดทดสอบ
```bash
# ติดตั้ง dependencies ข้ามทุกแพ็กเกจใน Monorepo
melos bootstrap

# ตรวจสอบคุณภาพโค้ดและ Lint rules
melos run analyze

# รันชุดทดสอบ Unit และ Integration Tests ทั้งหมด
melos run test
```

---

## 5. กฎระเบียบและแนวทางการส่งงาน (Contribution & Branching)
โปรดอ่านรายละเอียดใน [CONTRIBUTING.md](CONTRIBUTING.md) ก่อนเริ่มเขียนโค้ดและแตกกิ่ง Feature

