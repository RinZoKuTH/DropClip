# DropClip Engineering Playbook & Contributing Guide

คู่มือแนวทางการทำงานร่วมกันสำหรับทีมพัฒนาโครงการ DropClip ทั้ง 5 คน อ้างอิงตาม `docs/00-PROJECT-PROPOSAL-AND-PLAYBOOK.md`

---

## 1. กฎ 6 ข้อที่ห้ามละเมิด (Non-Negotiable Rules)

1. **Pull Request ห้ามเกิน 400 บรรทัด** (ไม่นับ generated code) — หากเกินแสดงว่า Task ใหญ่เกินไป ต้องซอย Task ย่อยทันที
2. **ห้าม Merge โค้ดที่ไม่มี Test** — ทุก PR ต้องมี Unit Test ครอบคลุม Happy path และ Edge cases อย่างน้อย 3 รูปแบบ
3. **Spike Task มี Timebox ไม่เกิน 4 ชั่วโมง** — หากติดปัญหาเกิน 4 ชั่วโมง ต้องหยุดและขอความช่วยเหลือจาก Lead/เพื่อนร่วมทีมทันที
4. **ห้าม Implement Cryptographic Primitives เอง** — ทุกอย่างต้องใช้ TLS 1.3 และ Secure Keystore มาตรฐานของระบบปฏิบัติการ
5. **ห้ามโหลดไฟล์ทั้งก้อนขึ้นหน่วยความจำ (RAM)** — หากพบคำสั่ง `readAsBytes()` สำหรับงานประมวลผลไฟล์ ให้ Reject PR ทันที (บังคับใช้ Streaming 1 MiB chunk)
6. **ใช้ Conventional Commits เสมอ** — เพื่อรองรับ Automated Changelog และ Traceability

---

## 2. ลำดับขั้นตอนการพัฒนา (Workflow)

```
1. รับ Ticket จาก docs/02-TICKETS.md
2. แตก Branch ออกจาก main:
   - Feature:  git checkout -b feat/<TICKET_ID>-<slug>
   - Spike:    git checkout -b spike/<SPIKE_ID>-<slug>
   - Bug fix:  git checkout -b fix/<TICKET_ID>-<slug>
3. เขียน Test ก่อนหรือพร้อมกับโค้ด
4. ตรวจสอบคุณภาพโค้ดก่อน Commit:
   - melos run format
   - melos run analyze
   - melos run test
5. เปิด Pull Request พร้อมกรอก Checklist ตาม PR Template
6. ได้รับ Code Review Approved อย่างน้อย 1 คน (งานด้าน Security ต้องผ่าน LEAD)
7. Squash and Merge เข้าสู่ main
```

---

## 3. รูปแบบข้อความ Commit (Commit Message Convention)

```
<type>(<scope>): <short description> (<TICKET_ID>)

ตัวอย่าง:
feat(discovery): implement mdns advertiser and browser (T1.1)
fix(clipboard): resolve suppression window race condition (T1.9)
test(protocol): add sas conformance test vectors (T0.2)
```

ประเภทของ Type:
- `feat`: ฟีเจอร์ใหม่
- `fix`: แก้ไขบั๊ก
- `refactor`: ปรับโครงสร้างโค้ดโดยไม่เปลี่ยนพฤติกรรม
- `test`: เพิ่มหรือแก้ไขชุดทดสอบ
- `docs`: แก้ไขเอกสาร
- `chore`: งานทั่วไปหรือการอัปเดต dependencies
