# Work Log — [<TICKET_ID>]: <Ticket Title>

| รายการ | รายละเอียด |
|---|---|
| **Ticket ID** | `<TICKET_ID>` (เช่น `T1.1`) |
| **Branch Name** | `<type>/<TICKET_ID>-<slug>` (เช่น `feat/T1.1-mdns-discovery`) |
| **Developer / Assignee** | ชื่อ-นามสกุล (ชื่อเล่น) |
| **Role Code** | `LEAD` / `DESK` / `MOB` / `NET` / `QA` |
| **AI Assistant Used** | Antigravity / Cursor / Copilot / Claude Code / Windsurf / None |
| **Start Date** | วกก-ดด-ปปปป (เช่น 2026-10-12) |
| **Completion Date** | วกก-ดด-ปปปป |
| **Status** | `IN PROGRESS` / `READY FOR REVIEW` / `MERGED` |

---

## 1. Objective & Scope (วัตถุประสงค์และขอบเขต)
- [ ] สิ่งที่ต้องส่งมอบข้อที่ 1
- [ ] สิ่งที่ต้องส่งมอบข้อที่ 2
- [ ] สิ่งที่ต้องส่งมอบข้อที่ 3

---

## 2. Technical Context & Key Decisions (การตัดสินใจเชิงเทคนิค)
* **การตัดสินใจที่ 1:** เหตุผลและที่มา (อ้างอิง Protocol Spec §... หรือ ADR-...)
* **การตัดสินใจที่ 2:** ทำไมถึงไม่ใช้วิธีอื่น
* **การรักษา Invariants:** ตรวจสอบว่าไม่ละเมิด Zero-Cloud, Streaming 1 MiB, Zero PIN on Wire, etc.

---

## 3. Files Created & Modified (รายการไฟล์ที่มีการเปลี่ยนแปลง)
- `path/to/file1.dart`: คำอธิบายการแก้ไข
- `path/to/file2.dart`: คำอธิบายการแก้ไข
- `test/path/to/file_test.dart`: รายละเอียดชุดทดสอบที่เพิ่ม

---

## 4. Verification & Testing Evidence (หลักฐานการทดสอบ)
- **Format & Lint:**
  ```bash
  melos run format   # Output: No changes
  melos run analyze  # Output: No issues found!
  ```
- **Test Output:**
  ```bash
  melos run test
  # Output: All tests passed! (X passed, 0 failed)
  ```
- **Coverage Summary:**
  - Package coverage: `XX%` (เกณฑ์ขั้นต่ำ $\ge 75\%$)

---

## 5. Reviewer Notes & Next Steps (บันทึกสำหรับผู้ตรวจและขั้นตอนต่อไป)
- **คำแนะนำสำหรับ Reviewer:** จุดที่ควรตรวจสอบเป็นพิเศษ
- **สิ่งที่ต้องทำต่อใน Ticket ถัดไป:** งานที่ต้องส่งต่อให้เพื่อนร่วมทีม

