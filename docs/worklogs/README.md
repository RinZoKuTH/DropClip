# DropClip — Engineering & AI Work Logs System
# (คู่มือการบันทึกประวัติการพัฒนาและสมุดบันทึกการทำงาน)

เพื่อรักษาความโปร่งใส ความต่อเนื่องของงาน (Engineering Continuity) และรองรับการทำงานร่วมกันระหว่างสมาชิกในทีมทั้ง 5 คนรวมถึง AI Coding Assistants (Cursor, Copilot, Windsurf, Claude Code, Antigravity):

> **กฎเหล็ก:** ทุกครั้งที่ทีมงานหรือ AI เริ่มต้นทำงานบน Branch ของตนเอง **จะต้องบันทึกประวัติการทำงาน (Work Log)** ลงในไดเรกทอรีนี้เสมอ

---

## 1. วิธีการบันทึก Work Log (ขั้นตอนปฏิบัติ)

มี 2 รูปแบบที่สามารถเลือกใช้ได้:

### รูปแบบ ก: สร้างไฟล์แยกตาม Ticket (แนะนำสำหรับ Feature ใหญ่)
1. คัดลอกเทมเพลตจาก [`docs/worklogs/TEMPLATE.md`](file:///c:/Users/UsEr/Documents/GitHub/DropClip/docs/worklogs/TEMPLATE.md)
2. บันทึกเป็นไฟล์ใหม่ตามชื่อ Ticket และ Branch เช่น:
   `docs/worklogs/<TICKET_ID>-<branch-slug>.md`
   *(ตัวอย่าง: `docs/worklogs/T1.1-mdns-discovery.md`)*
3. อัปเดตไฟล์นี้ต่อเนื่องขณะพัฒนาและทดสอบโค้ดใน Branch ของคุณ

### รูปแบบ ข: บันทึกต่อท้ายในสมุดบันทึกกลาง (`WORK_LOG.md`)
สำหรับงาน Spike, Task เล็ก, หรือการปรับปรุงเอกสาร สามารถเพิ่มหัวข้อใหม่ต่อท้ายใน [`docs/worklogs/WORK_LOG.md`](file:///c:/Users/UsEr/Documents/GitHub/DropClip/docs/worklogs/WORK_LOG.md) ได้โดยตรงตามโครงสร้างเทมเพลต

---

## 2. หัวข้อที่ต้องบันทึกใน Work Log (Mandatory Sections)

ทุกบันทึกต้องครอบคลุม 6 ประเด็นหลัก:
1. **Metadata:** Ticket ID, ชื่อนามสกุลและ Role Code ของผู้ทำ (`LEAD`, `DESK`, `MOB`, `NET`, `QA`), ชื่อ Branch, วันที่เริ่มต้น-สิ้นสุด
2. **Objective & Scope:** วัตถุประสงค์ของงานและขอบเขตที่ต้องส่งมอบ
3. **Key Architectural Decisions & Rationale:** การตัดสินใจเชิงเทคนิค เหตุผลที่เลือกใช้วิธีนี้ และผลกระทบต่อส่วนอื่น
4. **Changes Implemented:** รายการไฟล์ที่สร้าง/แก้ไข และคำอธิบายการทำงานโดยย่อ
5. **Verification & Test Results:** ผลการรัน Unit Test, Integration Test, Code Coverage และคำสั่งที่ใช้ตรวจสอบ
6. **Blockers & Residual Risks:** อุปสรรคที่พบ การแก้ไข หรือความเสี่ยงที่ต้องระวังต่อใน Ticket ถัดไป
