# DropClip — Chronological Engineering Master Log
# (สมุดบันทึกประวัติการพัฒนาโครงการ DropClip ส่วนกลาง)

เอกสารนี้รวบรวมประวัติการพัฒนา การตัดสินใจทางเทคนิค และการตรวจสอบความถูกต้องของโครงการ DropClip เรียงตามลำดับเวลา

---

## [2026-10-13] PCR-02: Comprehensive Peer Review Corrections & ISO 29148 Realignments

| รายการ | รายละเอียด |
|---|---|
| **Scope** | SRS v1.3 (ISO/IEC/IEEE 29148 & IEEE 830), Threat Model v2.1 (CVSS v3.1 recalculations), Tickets v2.1 (workload rebalance & dependency unlock), Release Plan v2.1 (osv-scanner & OSS signing), Playbook v2.1, Core Frameworks (T0.3 LoggingScrubber & T0.4 TestCluster) |
| **Branch** | `main` |
| **Engineers** | ทั้งทีม (`LEAD`, `DESK`, `MOB`, `NET`, `QA`) |
| **AI Assistant** | Antigravity AI Pair Programmer |
| **Status** | `COMPLETED & VERIFIED` |

### 1. วัตถุประสงค์
แก้ไขข้อบกพร่องเชิงระบบที่ตรวจพบในรายงาน Peer Review ครอบคลุมเอกสารทั้ง 6 ฉบับ และสร้างโค้ดส่วนของ Core Frameworks:
1. ปรับปรุง SRS ให้ได้มาตรฐานวิชาชีพสากล ISO/IEC/IEEE 29148 และ IEEE 830 (เพิ่ม Use Cases, MoSCoW, Rationale, Verification Methods, แก้ไขผลสำรวจเป็นแผนเก็บข้อมูลเพื่อความซื่อสัตย์ทางวิชาการ)
2. แก้ไขการคำนวณคะแนน CVSS v3.1 ในแบบจำลองภัยคุกคาม และเพิ่มภัยคุกคามที่ยังตกหล่น (T-I04, T-D04, T-T04, T-E03, T-R03)
3. ปลดล็อก Dependency T0.1 ออกจาก S0.1 และเกลี่ยภาระงาน Phase 2 & 3 ระหว่าง MOB, LEAD, และ NET
4. แทนที่ `dart pub audit` ด้วย `osv-scanner` และเพิ่มแนวทางการลงนามสำหรับโครงงานโอเพนซอร์ส/นักศึกษา
5. ซิงก์ค่าตัวชี้วัดแบตเตอรี่และการเพิกถอนสิทธิ์ใน Playbook ให้สอดคล้องกับ SRS
6. พัฒนาโค้ดรูปธรรมสำหรับ `LoggingScrubber` (T0.3) และ `TestCluster` (T0.4) พร้อม Unit Tests ครบถ้วน

### 2. การตัดสินใจทางเทคนิคและการแก้ไข (Key Implementations)
1. **SRS Revision (ISO/IEC/IEEE 29148:2018 & IEEE 830-1998):**
   - เพิ่มประวัติการแก้ไขและปรับสถานะเอกสารเป็น `Draft / Under Review` เพื่อความสมจริงก่อนการสอบประเมินโครงงาน
   - เพิ่ม Use Cases ตาราง UC-01 ถึง UC-12 ครอบคลุมทุกสถานการณ์ใช้งาน
   - ใส่ MoSCoW priority, Rationale, และ Verification Methods (Test, Inspection, Analysis, Demonstration) ใน FR-01 ถึง FR-12
   - ปรับแก้ข้อมูลใน §2.2 / §2.3.1 เป็น "แผนการเก็บรวบรวมข้อมูลและการวิเคราะห์เบื้องต้น (Data Gathering Plan & Preliminary Analysis)" และตัดตัวเลข 68% ที่ยังไม่ได้สำรวจจริงออกเพื่อความซื่อสัตย์ทางวิชาการ
   - เพิ่มข้อกำหนด NFR-M01 (Maintainability $\ge 75\%$), NFR-L01 (Localization TH/EN), NFR-A01 (Accessibility WCAG AA) และจัดทำ Traceability Matrix ครบ 100%
2. **Threat Model Recalculations & Additional Threats:**
   - คำนวณคะแนน CVSS v3.1 ใหม่ตรงตามมาตรฐาน: T-S02 (6.4 Medium), T-S03 (7.3 High), T-S04 (8.1 High), T-I01 (6.2 Medium)
   - เพิ่มภัยคุกคามใหม่: T-I04 (mDNS passive surveillance), T-D04 (Pairing handshake DoS), T-T04 (Co-located pastejacking), T-E03 (Auto-accept drive-by exploitation), T-R03 (Stale revocation replay)
   - ระบุช่องทางรายงาน GHSA ในข้อกำหนดการเปิดเผยช่องโหว่
3. **Tickets & Workload Balancing:**
   - ปลดล็อก Dependency ของ T0.1 ออกจาก S0.1 เพื่อให้เริ่มงานโครงสร้าง Monorepo ได้ทันที
   - มอบหมายงานร่วม: T2.1 (`MOB` + `LEAD`), T2.3 (`MOB` + `NET`), T2.4 (`NET` + `MOB`), T3.2 (`MOB` + `LEAD`), T3.4 (`NET` + `MOB`) เพื่อป้องกันภาวะคอขวดเดี่ยวของ MOB
4. **Supply Chain & Deployment Clarity:**
   - เปลี่ยนคำสั่งตรวจสอบช่องโหว่ใน CI เป็น `osv-scanner` (Google OSV)
   - เพิ่มคำอธิบายช่องทาง Open-Source & Student Project Signing และคำแนะนำสำหรับ Windows SmartScreen
5. **Concrete Scaffold Implementations (T0.3 & T0.4):**
   - พัฒนา `LoggingScrubber`: สกัดกั้น PEM Private Keys, Passwords, PINs, และ Clipboard Raw Payloads อัตโนมัติ พร้อมฟอร์แมต JSON Lines
   - พัฒนา `TestCluster`: รองรับการจำลอง In-Memory Multi-Device Mesh, Network Partitioning/Healing, Latency & Packet Loss Injection, และ HLC Clock Synchronization
   - พัฒนา Unit Tests ครบ 100% ใน `packages/dropclip_core/test/`

---

## [2026-10-13] PCR-01: Protocol & Architectural Alignment (Peer Review Findings)

| รายการ | รายละเอียด |
|---|---|
| **Scope** | Protocol Spec v2.1 (PCR-01), Dual Nonce SAS, HLC Drift & Parsing, Path Sanitizer Hardening, Playbook Alignment |
| **Branch** | `main` |
| **Engineers** | `LEAD` (เจ), `NET` (นนท์), `MOB` (เกื้อ), `QA` (ตามด) |
| **AI Assistant** | Antigravity AI Pair Programmer |
| **Status** | `COMPLETED & VERIFIED` |

### 1. วัตถุประสงค์
แก้ไขจุดขัดแย้งเชิงโครงสร้างและช่องว่างของข้อกำหนดตามรายงาน Peer Review:
1. ความขัดแย้งของ Endpoint จับคู่ระหว่าง §9.2 กับ §5.4 (ขาด `/pair/finalize`, schema เก่าไม่มี `commitment_B`)
2. Conformance Test Vector §18.1 ขัดกับสูตร Dual Nonce SAS §5.5.1
3. ข้อความตกค้างของ Lamport Clock ใน HTTP Header §9.4, §9.5, §10.7 และ Playbook
4. ค่า `MAX_CLOCK_DRIFT` (60 วินาที) ขาดหายไปจากตาราง §16 และ `constants.dart`
5. การป้องกันการโจมตี Unicode Bidi Override และ Windows Device Name ที่ตกสำรวจใน `path_sanitizer.dart`
6. การลบ `derivePinNonce()` ที่ขัดกับหลักการ Zero-PIN-on-Wire

### 2. การตัดสินใจทางเทคนิคและการแก้ไข (Key Implementation Details)
1. **Pairing Endpoints Realignment (§9.1, §9.2 & §5.4):**
   - อัปเดต `POST /api/v1/pair` ให้รับ `commitment_B` และส่ง `nonce_A`
   - เพิ่ม `POST /api/v1/pair/finalize` (Step 13) เพื่อรับผลการยืนยัน SAS (`match`/`mismatch`) จากผู้ใช้
   - ระบุชัดเจนว่าห้ามส่ง PIN หรือ nonce ที่ derive จาก PIN บนเครือข่ายเด็ดขาด
2. **Dual Nonce SAS Conformance & Zero-PIN Enforcement:**
   - คำนวณและยืนยัน Test Vector §18.1 แบบ Dual Nonce 160 bytes: ได้ผลลัพธ์ `"337017"`
   - ตรวจสอบ Test Vector §18.2 แบบ PIN mode: ได้ผลลัพธ์ `"639589"` ตรงตามสเปก 100%
   - ใส่ `@Deprecated` ให้ `calculateSas` (legacy single-nonce) และนำ `calculateSasDual` เป็นแกนหลัก
   - ลบ `derivePinNonce()` ออกจาก `sas.dart` และ `bench.dart` อย่างสมบูรณ์
   - เพิ่ม Input Validation ตรวจ 64-character hex สำหรับ fingerprint, 6-digit สำหรับ PIN, และ 16-byte สำหรับ nonces
3. **HLC Clock Drift Enforcement & Wire Formatting:**
   - กำหนด `ClockDriftException` ใน `hlc.dart` ตรวจจับเมื่อ `remote.l - physicalTimeMs > 60000` ms ใน `merge()`
   - Normalization ของ `d` (lowercase, trim) เพื่อความเที่ยงตรงของ LWW Tie-breaking
   - เพิ่ม `Hlc.parse()` และ `Hlc.tryParse()` รองรับรูปแบบ header `X-DropClip-HLC: <l>:<c>:<d>`
   - เพิ่ม `MAX_CLOCK_DRIFT` (60s) และ `MIN_SUPPORTED_VERSION` (1) ใน `constants.dart` และตาราง §16
4. **Path Sanitizer Hardening:**
   - บล็อก Unicode Bidirectional Override characters (`\u202A`–`\u202E`, `\u2066`–`\u2069`) ป้องกันเทคนิค RLO ซ่อนนามสกุลไฟล์
   - เพิ่มรายการ DOS/Windows Device Aliases: `CONIN$`, `CONOUT$`, `COM¹`–`COM³`, `LPT¹`–`LPT³`
   - เพิ่มฟังก์ชัน `validateOfferPaths(List<String> paths)` ตรวจจับ Case-insensitive Collisions ก่อนรับไฟล์
5. **Specification & Playbook Cleanup:**
   - แก้ไขเลขหัวข้อซ้ำ `7.4.11 error` เป็น `7.4.12 error`
   - ปรับข้อความ S0.1 ใน §19 และ T1.2 ใน `02-TICKETS.md` เป็น ECDSA P-256 ตาม ADR-006
   - ปรับปรุงข้อความ ADR-008 ใน Playbook บรรทัด 318 ให้ระบุเงื่อนไขการจำกัด Clock Drift ด้วย 60s Bound และ Trade-off ของเครื่องออฟไลน์อย่างถูกต้อง

### 3. ผลการทดสอบ (Verification)
- Automated Conformance Vector Runner (Python & Dart algorithms):
  - Dual Nonce QR SAS (`160 bytes`): `337017` $\to$ PASS
  - Legacy Single Nonce QR SAS (`144 bytes`): `579318` $\to$ PASS
  - Salted PIN Mode SAS (`187 bytes`): `639589` $\to$ PASS
  - HLC Merge & Clock Drift Rejection (>60s): PASS
  - Path Sanitizer Attack Vectors (Bidi RLO, Windows Reserved Devices, Offer Collision): PASS 100%

---

## [2026-10-12] Phase 0 Architectural Realignment & Blocker Resolutions

| รายการ | รายละเอียด |
|---|---|
| **Scope** | Core Architecture, Protocol Spec v2.0, Threat Model, Release Plan, SAS Engine |
| **Branch** | `main` / `develop` (Merged Commit: `06cada3`) |
| **Engineers** | ทั้งทีม (`LEAD`, `DESK`, `MOB`, `NET`, `QA`) |
| **AI Assistant** | Antigravity AI Pair Programmer |
| **Status** | `COMPLETED & MERGED` |

### 1. วัตถุประสงค์
- ปลดล็อก 5 ปัญหาสำคัญก่อนเริ่มงาน (Phase 0 Blockers):
  1. ความปลอดภัยของ PIN Mode (ตัด Offline Dictionary Attack $10^6$)
  2. ความไม่สอดคล้องกันของการเจรจา Protocol Versioning
  3. ช่องโหว่ของ Revocation Gossip (เครื่องที่ถูกขโมย revoke เครื่องจริง และเครื่องออฟไลน์ไม่ได้รับข่าว)
  4. ขนาดเพย์โหลดคลิปบอร์ดที่ระบุไม่ตรงกันในเอกสาร
  5. การเกลี่ยภาระงานของทีมให้สมดุล (LEAD มีงานล้นมือใน Phase 1)

### 2. การตัดสินใจเชิงสถาปัตยกรรมที่สำคัญ
1. **Zero PIN on Wire Architecture:**
   - ตัดการส่ง PIN หรือ Hash ของ PIN บนสายเครือข่ายออก 100%
   - กำหนดให้ PIN ทำหน้าที่เป็น Out-of-Band (OOB) Salt ร่วมกับ Commit-then-Reveal:
     $$\text{SAS} = \text{SHA-256}(\text{fp}_{lo} \parallel \text{fp}_{hi} \parallel N_A \parallel N_B \parallel \text{"dropclip-pin-salt-v1:"} \parallel \text{UTF8}(\text{PIN})) \bmod 10^6$$
   - ป้องกัน Active MITM ที่ไม่มี Oracle ตรวจสอบ PIN เดา
2. **Version Negotiation Harmonization:**
   - ใช้กติกาช่วงซ้อนทับ $\min(\text{local.v}, \text{remote.v}) \ge \max(\text{local.min\_v}, \text{remote.min\_v})$
   - หากตกลงไม่ได้ ให้ปิดด้วย Close Code `4003` (`E_UNSUPPORTED_VERSION`)
3. **Revocation Defenses:**
   - เพิ่มกฎ **No Self-Revocation by Proxy** เพื่อป้องกันเครื่องที่ถูกขโมยชิงส่งคำสั่งทำลายเครื่องจริง
   - บันทึก `revoked_tombstones.json` ถาวร และทำ Handshake Anti-Entropy แลกเปลี่ยน `tombstones_hash` ใน `hello` / `hello.ack`
4. **Explicit Size Quotas:**
   - Control Plane Frame max = 64 KiB, Inline text max = 32 KiB, Blob threshold = > 32 KiB, Total max content = 32 MiB
5. **Team Workload Rebalance:**
   - T1.6 (macOS Watcher) โอนให้ `DESK`
   - T1.7 (Windows Watcher) โอนให้ `NET`
   - T3.1 (iOS Discovery NWBrowser) มอบหมายให้ `LEAD` ทำร่วมกับ `MOB`

### 3. ไฟล์ที่มีการเปลี่ยนแปลง
- `docs/01-PROTOCOL-SPEC.md`: ปรับปรุง Protocol Spec v2.0 ครบทุก Section
- `docs/02-TICKETS.md`: ปรับปรุง Role Dedication, RTM, T1.3, T1.6, T1.7, T3.1, T4.3, GATE-4 และ Workload Summary
- `docs/03-SRS.md`: ปรับปรุง FR-02, FR-10, FR-11, NFR-S04, CI-02, OS target phrasings
- `docs/04-THREAT-MODEL.md`: เพิ่ม Asset A-07, ปรับปรุง STRIDE, Attack Tree 1, Section 9 Vulnerability Disclosure
- `docs/05-RELEASE-AND-UPDATE-PLAN.md`: ปรับเป็น Roll-Forward, Schema Versioning, iOS Phased Release, Thai Code Signing
- `.well-known/security.txt`: เพิ่มไฟล์มาตรฐาน RFC 9116
- `packages/dropclip_protocol/lib/src/sas.dart`: เพิ่มฟังก์ชัน `calculateSasPinMode()`
- `packages/dropclip_protocol/test/sas_test.dart`: เพิ่ม Conformance Test Vector `"639589"`

### 4. การตรวจสอบและทดสอบ (Verification)
- ทดสอบ SAS Test Vector Conformance:
  - QR Mode Test Vector: `"482910"` $\to$ PASS
  - PIN Mode Test Vector: `"639589"` $\to$ PASS
  - Symmetry Check: Host และ Client คำนวณได้ค่าเดียวกัน $\to$ PASS
  - Wrong PIN Rejection: PIN ไม่ตรงได้ผลลัพธ์ต่างกัน $\to$ PASS

---

## [2026-10-12] Monorepo & Baseline Setup

| รายการ | รายละเอียด |
|---|---|
| **Scope** | Monorepo Setup, Melos, Packages Scaffold, CI/CD Workflows |
| **Branch** | `main` (Commit: `4d8270f`) |
| **Engineers** | `LEAD` (เจ), `QA` (ตามด) |
| **Status** | `COMPLETED` |

### 1. วัตถุประสงค์
- วางรากฐาน Monorepo ด้วย Melos จัดการ 5 Core Packages, 2 Apps, และ 2 Tools
- สร้าง GitHub Actions CI สำหรับ Melos Bootstrap, Formatting, Analyzing และ Unit Testing
- วางรากฐาน Testing Matrix สำหรับ Linux, macOS, และ Windows runners

