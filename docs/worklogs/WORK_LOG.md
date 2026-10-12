# DropClip — Chronological Engineering Master Log
# (สมุดบันทึกประวัติการพัฒนาโครงการ DropClip ส่วนกลาง)

เอกสารนี้รวบรวมประวัติการพัฒนา การตัดสินใจทางเทคนิค และการตรวจสอบความถูกต้องของโครงการ DropClip เรียงตามลำดับเวลา

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

