# DropClip Wire Protocol Specification

| รายการ | รายละเอียด |
|---|---|
| **รหัสเอกสาร** | PROTO-DC-V2.0 |
| **Protocol Version (`PROTOCOL_VERSION`)** | `1` (ยังไม่เคย ship — การแก้ไขในเอกสารฉบับนี้จึงไม่ขยับเลขโปรโตคอล) |
| **Document Version** | 2.0 — Realigned to SRS-DC-V1.2 |
| **สถานะ** | Frozen for Phase 1 (แก้ได้เฉพาะผ่าน Protocol Change Request — ดู §0.3) |
| **Owner** | Team Lead (เจ) |
| **เอกสารอ้างอิง** | `00-PROJECT-PROPOSAL-AND-PLAYBOOK.md` (v2.0), `02-TICKETS.md` (v2.0), `03-SRS.md` (SRS-DC-V1.2) |

---

## 0. Document Control

### 0.1 ขอบเขตของเอกสาร

เอกสารนี้คือ **"สัญญากลาง" (Contract)** ระหว่างทุก component ของ DropClip ตามหลักการ Playbook §11 — *Lead รับผิดชอบสัญญา ทีมรับผิดชอบการเติมเต็ม* ครอบคลุม:

1. Wire protocol ทั้ง 3 plane (Discovery / Control / Data)
2. Algorithm เชิงบรรทัดฐาน (Normative) ของ Clipboard Sync, Pairing, Resume
3. **Platform Channel Contract** ระหว่าง Dart ↔ Native (เพื่อให้ทีม Desktop/Mobile/Engine ทำงานขนานกันได้)
4. **Local Persistence Schema** ของ Entity E-01 ถึง E-06 ตาม SRS §2.3.2
5. Constants, Error Codes และ Conformance Test Vectors ที่ทุกแพลตฟอร์มต้องให้ผลตรงกัน

### 0.2 SRS Traceability

| หัวข้อในเอกสารนี้ | SRS Requirement |
|---|---|
| §3 Discovery | FR-01, SF-01, CI-01, NFR-P04, E-03 |
| §4 Identity & Transport Security | FR-02, FR-08 (step 1), NFR-S01, NFR-S02, SW-02, E-01 |
| §5 Pairing | FR-02, SF-02, UI-03, HW-02 |
| §6 Connection Management | FR-10, NFR-RE03, CI-02 |
| §7 Control Plane Messages | FR-03A/B/C, FR-04, FR-07, FR-11 |
| §9 Data Plane | FR-03C, FR-07, FR-08, FR-09, CI-03 |
| §10 Clipboard Sync Algorithm | FR-03A, FR-03B, FR-03C, FR-04, FR-05, SF-03, SF-05, NFR-RE02 |
| §11 Image Normalization | FR-06, SF-04, NFR-P02, NFR-P05 |
| §12 File Transfer | FR-07, FR-08, FR-09, SF-06, SF-07, NFR-P03, NFR-R01, NFR-RE01 |
| §13 Revocation | FR-11, SF-08, NFR-S05 |
| §14 Platform Channel Contract | FR-03A/B/C, FR-05, FR-12, SW-01, SW-03 |
| §15 Persistence Schemas | E-01 … E-06, FR-12 |
| §17 Security | NFR-S01 … NFR-S05 |

### 0.3 Protocol Change Request (PCR)

- การเปลี่ยนแปลงใด ๆ ต่อเอกสารนี้ MUST ทำผ่าน PR ที่มี label `protocol` และ MUST ได้รับ approve จาก LEAD
- การเปลี่ยนที่ทำให้ wire format ไม่เข้ากันหลัง Phase 1 ship แล้ว MUST ขยับ `PROTOCOL_VERSION`
- ทุก PCR MUST อัปเดต §20 Change Log และ conformance test ใน `packages/dropclip_protocol/test/`

---

## 1. Conventions

- คำว่า **MUST / MUST NOT / SHOULD / SHOULD NOT / MAY** ตีความตาม RFC 2119
- Byte string ใน JSON MUST เข้ารหัสเป็น **Base64 standard (RFC 4648 §4, with padding)**
- Hash ทุกตัว MUST เป็น **SHA-256 แสดงผลเป็น lowercase hex 64 ตัวอักษร**
- Timestamp ทุกตัว MUST เป็น **Unix epoch milliseconds (int64, UTC)**
- UUID ทุกตัว MUST เป็น **UUID v4, lowercase, มี hyphen**
- JSON MUST เป็น UTF-8 ไม่มี BOM; ผู้รับ MUST ignore field ที่ไม่รู้จัก (forward-compatible) แต่ MUST reject เมื่อ field ที่ required ขาดหรือผิด type
- ชื่อไฟล์และชื่ออุปกรณ์บน wire SHOULD อยู่ในรูป Unicode **NFC**
- หน่วย: `KiB = 1,024 bytes`, `MiB = 1,048,576 bytes`

---

## 2. Overview

### 2.1 Planes

| Plane | Transport | หน้าที่ | Limit |
|---|---|---|---|
| **Discovery** | mDNS/DNS-SD, UDP 5353 (RFC 6762/6763) | ค้นหา/ประกาศอุปกรณ์ใน subnet เดียวกัน | TXT ≤ 255 B/entry |
| **Control** | WebSocket over TLS 1.3 (`/api/v1/ws`) | signaling, clipboard ≤ 32 KiB, metadata ไฟล์ | `WS_MAX_MESSAGE_SIZE` = 64 KiB / message |
| **Data** | HTTP/1.1 Chunked over TLS 1.3 | ไฟล์, clipboard blob > 32 KiB, one-shot clipboard (Tier 2/3) | ไม่จำกัด (streaming) |

Control และ Data plane MUST ให้บริการบน **HTTPS server ตัวเดียวกัน พอร์ตเดียวกัน** ในช่วง TCP `53317–53417` (CI-02, CI-03)

> **ทำไม WS limit = 64 KiB แต่ inline threshold = 32 KiB:** SRS กำหนดให้ clipboard payload ≤ 32 KiB ส่งผ่าน Control Plane — แต่ payload ถูก base64 (ขยาย 4/3 เท่า) แล้วห่อด้วย envelope ทำให้ข้อความจริงใหญ่ได้ถึง ~44 KiB จึงตั้ง limit ของ frame ไว้ที่ 64 KiB

### 2.2 Capability Tiers (SRS §1.3.2)

| Tier | `os` | Clipboard Outbound (อ่านจากเครื่องนี้) | Clipboard Inbound (เขียนลงเครื่องนี้) | File Transfer |
|---|---|---|---|---|
| **1 — Full Passive** | `macos`, `windows` | อัตโนมัติ (Native Watcher) | อัตโนมัติ | เต็มรูปแบบ |
| **2 — Assisted** | `android` | 1-Click: QS Tile / Notification Action / Share Sheet | อัตโนมัติ (Foreground Service → `setPrimaryClip`) | เต็มรูปแบบ |
| **3 — Manual-Assist** | `ios` | Share Extension / Widget / Action Button / Shortcuts | เมื่อแอปอยู่ foreground หรือผู้ใช้แตะ Widget (Catch-up) | เต็มรูปแบบ (ขณะแอป active) |

Tier ของอุปกรณ์ MUST ถูกประกาศใน mDNS TXT (`tier`) และใน `hello` (`tier`) และ MUST สอดคล้องกับ `os`

### 2.3 Topology

- อุปกรณ์ที่ trusted และ online เชื่อมต่อกันแบบ **Full Mesh** (สูงสุด `MAX_PEERS` = 8)
- **ไม่มี relay ใน v1:** อุปกรณ์ MUST NOT forward ข้อความที่ได้รับจาก peer หนึ่งไปยัง peer อื่น ดังนั้นใน v1 `origin` จะเท่ากับผู้ส่งเสมอ — แต่ผู้รับ MUST ยังคงตรวจ `origin` ตาม §10 (defense-in-depth และรองรับ relay ในอนาคต)

### 2.4 Version Negotiation

- ทุกฝ่าย MUST ประกาศ `v` ใน mDNS TXT, ใน `hello` และใน request body ของ `/api/v1/pair`
- ถ้า `v` ไม่ตรงกัน ฝ่ายรับ MUST ตอบ `error` code `E_VERSION_MISMATCH` (fatal) แล้วปิด connection
- **ไม่มี backward compatibility ใน Phase 1** — ตั้งใจเพื่อลดความซับซ้อน

---

## 3. Discovery Layer (FR-01)

### 3.1 Service Registration

```
Service Type : _dropclip._tcp.local
Instance Name: <device_id>             (UUID v4 — ไม่ใช้ชื่อเครื่องเพราะอาจซ้ำ/มีอักขระที่ mDNS ไม่รองรับ)
Port (SRV)   : พอร์ตที่ bind ได้จริงในช่วง 53317–53417
Record TTL   : 120 วินาที (MDNS_TTL)
```

### 3.2 TXT Record

| Key | Required | ค่า |
|---|---|---|
| `v` | ✅ | Protocol version — `"1"` |
| `id` | ✅ | Device UUID v4 (ต้องตรงกับ Instance Name) |
| `name` | ✅ | **Base64 ของชื่อเครื่อง UTF-8** — ชื่อ MUST ≤ 64 bytes ก่อน encode (ตัดที่ขอบ code point) |
| `os` | ✅ | `macos` \| `windows` \| `ios` \| `android` |
| `tier` | ✅ | `1` \| `2` \| `3` |
| `port` | ✅ | พอร์ต TCP (MUST เท่ากับ SRV port — สำรองไว้สำหรับแพลตฟอร์มที่ resolve SRV ไม่เสถียร) |
| `fp` | ✅ | SHA-256 hex ของ DER certificate (64 chars) |
| `cap` | ⬜ | Capability flags คั่นด้วย `,` — ดู §7.4.1 |

ตัวอย่าง:
```
v=1
id=550e8400-e29b-41d4-a716-446655440000
name=TWFjQm9vayBQcm8g4LiC4Lit4LiH4LmA4LiI
os=macos
tier=1
port=53317
fp=9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08
cap=clip.text,clip.image,clip.push,file,file.resume
```

> ⚠️ **TXT Record MUST NOT มีข้อมูลลับใด ๆ** (Private Key, Nonce, PIN, Secret) — ทุกคนในวง Wi-Fi อ่านได้
> `fp` เป็นข้อมูลสาธารณะ ปลอมไม่ได้เพราะต้องมี private key คู่กันจึงจะผ่าน TLS handshake

### 3.3 Browsing & Liveness

- Browser MUST ส่ง query ซ้ำทุก `DISCOVERY_QUERY_INTERVAL` (10 วินาที) และบันทึก `last_seen_at` ทุกครั้งที่ได้รับ response/announcement
- เมื่อแอปปิดตามปกติ MUST ส่ง goodbye packet (TTL = 0) → ผู้รับ MUST ลบ peer ทันที
- เมื่อ network interface เปลี่ยน (Wi-Fi ↔ Ethernet, IP เปลี่ยน) MUST re-announce ภายใน 5 วินาที
- Packet ที่ `v`/`id`/`fp`/`os`/`tier` ผิดรูปแบบ MUST ถูกทิ้งเงียบ ๆ (log ระดับ `debug`)
- IP ของ `device_id` เดิมเปลี่ยน → MUST update entry เดิม MUST NOT สร้างใหม่

### 3.4 Trust Classification (ฝั่ง client)

| เงื่อนไข | สถานะ | การกระทำ |
|---|---|---|
| `id` และ `fp` ตรงกับ record ใน Trusted Store | `trusted` | auto-connect ตาม §6.2 |
| `id` ไม่อยู่ใน Trusted Store | `untrusted` | แสดงใน UI เป็น "พร้อมจับคู่" เท่านั้น |
| `id` อยู่ใน Trusted Store แต่ `fp` ไม่ตรง | `identity_changed` | **MUST NOT auto-connect**, แสดงคำเตือน (อาจติดตั้งใหม่หรือถูกปลอม) — ผู้ใช้ต้อง pair ใหม่ |

### 3.5 Peer State Machine (E-03)

```
                 (fp ∈ trusted store)
 [DISCOVERED] ─────────────────────────▶ [TRUSTED_ONLINE] ──(TLS+hello ok)──▶ [CONNECTED]
      │                                        │                                 │
      │ ไม่เห็น > 30s                           │ ไม่เห็น > 30s                    │ WS ปิด
      ▼                                        ▼                                 ▼
   [STALE] ◀───────────────────────────────────┘                          [TRUSTED_ONLINE]
      │  (เห็นอีกครั้ง → กลับสถานะเดิม)
      │ ไม่เห็น > 120s
      ▼
  [REMOVED]  (ลบออกจาก memory)
```

- ไม่เห็นเกิน `DEVICE_STALE_TIMEOUT` (30 s) → MUST ทำเครื่องหมาย `stale` (UI แสดงเป็นสีจาง)
- ไม่เห็นเกิน `DEVICE_REMOVE_TIMEOUT` (120 s) → MUST ลบออกจาก Discovered Peer Cache
- Peer ที่ `CONNECTED` อยู่ MUST NOT ถูกทำ stale จาก mDNS เพียงอย่างเดียว (WS heartbeat เป็นตัวตัดสิน)

### 3.6 Fallback Discovery

เมื่อ mDNS ใช้ไม่ได้ (router drop multicast) MUST มี 2 ทางเลือก:

- **Fallback A — QR Code** (§5.3) — QR มี IP + port + fp ครบ
- **Fallback B — Manual Entry** — ผู้ใช้กรอก `IP:port` + PIN 6 หลักที่แสดงบนเครื่อง host (§5.4)

---

## 4. Identity & Transport Security

### 4.1 Device Identity (E-01)

| Property | Value |
|---|---|
| Device ID | UUID v4 สร้างครั้งแรกที่เปิดแอป |
| Key Algorithm | **Ed25519** |
| Certificate | X.509 v3 self-signed, serial = 16 random bytes |
| Subject / Issuer CN | `dropclip-<device_id>` |
| Validity | 10 ปี |
| Fingerprint (`fp`) | `SHA-256(DER(cert))` lowercase hex |
| Generation | ครั้งแรกเท่านั้น — ลบแอป/ติดตั้งใหม่ = identity ใหม่ (ไม่กู้ของเก่า) |

### 4.2 Private Key Storage (NFR-S02)

| OS | กลไก |
|---|---|
| macOS | Keychain (`kSecClassKey`/generic password, access: this device only) |
| iOS | Keychain พร้อม **Keychain Access Group ร่วมกับ Share Extension** ผ่าน App Group |
| Windows | DPAPI (`CurrentUser` scope) — เก็บเป็น blob ที่เข้ารหัสแล้วใน app data |
| Android | Android Keystore — API 33+ MAY เก็บ Ed25519 ตรง; API 29–32 MUST ห่อ (wrap) private key ด้วย AES-256-GCM key ที่อยู่ใน AndroidKeyStore |

> **Private key MUST NOT ปรากฏเป็น plaintext บนดิสก์ในทุกกรณี** — มี automated security test (grep หา PEM/DER/`BEGIN PRIVATE KEY` ทั้ง app data directory)

### 4.3 TLS Requirements (NFR-S01)

- MUST ใช้ **TLS 1.3 เท่านั้น** — MUST reject TLS 1.2 และต่ำกว่า (กัน downgrade)
- Cipher suites ที่อนุญาต: `TLS_AES_128_GCM_SHA256`, `TLS_AES_256_GCM_SHA384`, `TLS_CHACHA20_POLY1305_SHA256`
- MUST เป็น **mutual TLS** — server MUST request client certificate ทุก connection
- MUST verify peer ด้วย **SHA-256 fingerprint pinning** ไม่ใช้ CA chain

### 4.4 Pinning Logic

**ฝั่ง Client** — ตรวจ server cert ใน TLS callback:
```dart
bool verifyServer(X509Certificate cert, {String? expectedFp}) {
  final fp = sha256.convert(cert.der).toString();
  if (expectedFp != null) return fp == expectedFp;          // pairing ผ่าน QR / reconnect
  return trustedStore.containsFingerprint(fp);              // connection ปกติ
}
```

**ฝั่ง Server** — TLS handshake MUST สำเร็จแม้ client cert เป็น self-signed แล้วตรวจที่ application layer:
```dart
// ทุก request/upgrade ยกเว้น pairing endpoints
final fp = sha256.convert(request.certificate!.der).toString();
if (!trustedStore.containsFingerprint(fp)) {
  return Response(403, body: errorJson('E_NOT_PAIRED'));     // FR-08 step 1
}
```

> **เหตุผลที่ตรวจที่ application layer:** เพื่อให้ตอบ HTTP 403 + error code ได้ตาม FR-08 และ FR-11 แทนการตัด handshake เงียบ ๆ ซึ่ง debug ยาก

**ข้อยกเว้นเดียว:** `POST /api/v1/pair` และ `POST /api/v1/pair/confirm` อนุญาต client cert ที่ยังไม่ trusted ได้ แต่ MUST มี rate limit (§5.6) และ MUST ผ่าน SAS (§5.5)

> ⚠️ **Open Issue — Spike S0.1:** ต้องพิสูจน์ว่า Dart `SecureServerSocket`/`HttpClient` (BoringSSL), Apple Network.framework (Share Extension) และ Android รองรับ TLS 1.3 + Ed25519 self-signed + mutual auth ครบ หากไม่ได้ ทางเลือกสำรองคือ **ECDSA P-256** ซึ่ง MUST บันทึกเป็น ADR-006 และยื่น SRS Change Request (SRS ระบุ Ed25519)

---

## 5. Pairing Protocol (FR-02)

### 5.1 Pairing Session (ฝั่ง Host)

เมื่อผู้ใช้กด **"เพิ่มอุปกรณ์"** บนเครื่อง Host ระบบ MUST สร้าง pairing session:

| Field | ค่า |
|---|---|
| `nonce` | 16 random bytes (CSPRNG) |
| `pin` | 6 หลักสุ่ม (CSPRNG) `000000–999999` |
| `exp` | `now + PAIR_NONCE_TTL` (60 s) |
| `state` | `open` → `claimed` → `paired` \| `failed` \| `expired` |

Host MUST แสดงทั้ง **QR Code และ PIN** บนหน้าจอเดียวกัน (UI-03) และ session เป็นแบบ **single-use** — `/pair` ที่สำเร็จครั้งแรกทำให้ session เป็น `claimed` และ request ถัดไปถูกปฏิเสธ

### 5.2 Pairing Modes

| Mode | ใช้เมื่อ | Client รู้ `fp` ของ Host ล่วงหน้า? | `nonce` ที่ใช้ |
|---|---|---|---|
| `qr` | มือถือสแกน QR จาก Desktop | ✅ (จาก QR) → pin ได้ทันที | `nonce` จาก QR |
| `pin` | Desktop ↔ Desktop (เลือกจากรายการ Discovered) หรือ Manual IP | ❌ → พึ่ง SAS อย่างเดียว | `pin_nonce = SHA-256("dropclip-pin-v1:" ‖ pin)[0:16]` |

### 5.3 QR Payload

```json
{
  "t": "dropclip-pair",
  "v": 1,
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "ip": "192.168.1.42",
  "port": 53317,
  "fp": "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08",
  "nonce": "3q2+7wAAAAAAAAAAAAAAAA==",
  "exp": 1757280060000
}
```
Encode เป็น JSON (UTF-8) แล้วสร้าง QR ที่ error correction level **M**

### 5.4 Flow

```
Device A — Host (แสดง QR + PIN)                         Device B — Client (สแกน QR / กรอก PIN)
  │ 1. สร้าง session {nonce, pin, exp=+60s}                  │
  │ 2. แสดง QR + PIN ──────────────────────────────────────▶ │
  │                                                          │ 3. TLS 1.3 (mTLS ด้วย cert ของ B)
  │                                                          │    mode=qr: pin server fp = QR.fp
  │◀──────────── 4. POST /api/v1/pair ───────────────────────│
  │   {v, device_id, name, os, tier, fp, nonce, method}       │
  │ 5. ตรวจ: rate limit, session open, ยังไม่หมดอายุ,         │
  │    nonce ตรง (nonce หรือ pin_nonce), v ตรง,               │
  │    body.fp == SHA-256(client TLS cert)                    │
  │──────────── 6. 200 {pair_id, device_id, name, os, tier, fp} ─▶│
  │                                                          │ 7. ตรวจ body.fp == server TLS cert fp
  │ 8. ทั้งสองฝั่งคำนวณ SAS เอง (§5.5) แล้วแสดงตัวเลขใหญ่ 6 หลัก │
  │          [ผู้ใช้เทียบตัวเลขด้วยตา แล้วกด "ตรงกัน"/"ไม่ตรง" ทั้งสองเครื่อง]   │
  │◀──────────── 9. POST /api/v1/pair/confirm ───────────────│
  │   {pair_id, result: "match" | "mismatch"}                 │
  │   (long-poll จนผู้ใช้ฝั่ง A ตัดสิน, ≤ PAIR_CONFIRM_TIMEOUT)   │
  │──────────── 10. 200 {result: "paired"} | 401 E_SAS_FAILED ─▶│
  │ 11. ทั้งคู่บันทึกลง Trusted Store (E-02) เฉพาะเมื่อ "paired"   │
  │                                                          │ 12. B เปิด WS ตาม §6 ทันที
```

**กฎ:**
- Host MUST NOT ส่งค่า SAS ใน response — ทั้งสองฝั่ง MUST คำนวณ SAS เองอย่างอิสระ
- ผลลัพธ์เป็น `paired` ก็ต่อเมื่อ **ผู้ใช้ทั้งสองฝั่งกด "ตรงกัน"** เท่านั้น
- ถ้าฝั่งใดกด "ไม่ตรง" หรือหมดเวลา → ทั้งสองฝั่ง MUST ทิ้ง session และ MUST NOT บันทึกอะไรลง Trusted Store
- Host MUST นับ "ไม่ตรง" เป็น failed attempt ของ IP ฝั่ง Client (§5.6)

### 5.5 Short Authentication String (SAS)

```
fp_lo, fp_hi = sort_ascending([fp_A, fp_B])              // เทียบเป็น string lowercase hex
sas_input    = UTF8(fp_lo) ‖ UTF8(fp_hi) ‖ nonce_bytes    // 64 + 64 + 16 = 144 bytes
sas_hash     = SHA-256(sas_input)
sas_value    = uint32_big_endian(sas_hash[0..3]) mod 1_000_000
sas_display  = zero-pad 6 หลัก เช่น "042817" (UI MAY แสดงเป็น "042 817")
```

- `nonce_bytes` = ค่า `nonce` ที่ decode แล้ว (mode `qr`) หรือ `pin_nonce` (mode `pin`)
- **ทำไมต้อง sort:** ให้ทั้งสองฝ่ายได้ค่าเดียวกันโดยไม่ขึ้นกับว่าใครเริ่ม
- **ทำไมต้องมี SAS:** ถ้ามี MITM แทรกกลาง fingerprint ที่แต่ละฝั่งเห็นจะต่างกัน → เลข 6 หลักไม่ตรง → ผู้ใช้เห็นทันที (แนวคิดเดียวกับ ZRTP)
- Test vectors: §18.1, §18.2

### 5.6 Rate Limiting & Lockout

| เงื่อนไข | Limit | Response |
|---|---|---|
| `POST /api/v1/pair` | `PAIR_RATE_LIMIT` = 5 requests / นาที / IP | `429` + `Retry-After` + `E_RATE_LIMITED` |
| SAS ไม่ตรง / nonce ผิด ติดต่อกัน | 3 ครั้ง → lock IP นั้น `PAIR_LOCKOUT` = 5 นาที | `429` + `E_PAIR_LOCKED` |
| Session หมดอายุ | — | `410` + `E_NONCE_EXPIRED` |
| ไม่มี session / ถูก claim แล้ว / nonce ไม่ตรง | — | `401` + `E_PAIRING_INVALID` |

---

## 6. Connection Management (FR-10)

### 6.1 Endpoint

```
wss://<ip>:<port>/api/v1/ws        (mTLS + pinning ตาม §4)
```

### 6.2 Initiator Rule (กัน duplicate connection)

1. ถ้าฝั่งหนึ่งเป็นมือถือ (tier 2/3) และอีกฝั่งเป็น desktop → **มือถือเป็นผู้เริ่ม**
2. มิฉะนั้น → อุปกรณ์ที่ `device_id` น้อยกว่า (เทียบ string) เป็นผู้เริ่ม
3. ถ้าผู้เริ่มที่ควรเป็นยังไม่เชื่อมต่อภายใน `INITIATOR_GRACE` (10 s) นับจากเห็นกันใน mDNS อีกฝั่ง MAY เริ่มเอง
4. ถ้าเกิด 2 connection ระหว่างคู่เดียวกัน → MUST เก็บ connection ที่เริ่มโดย "ผู้เริ่มตามกฎข้อ 1–2" และปิดอีกเส้นด้วย close code `4001`

### 6.3 Session Handshake

1. หลัง WS upgrade ผู้เริ่ม MUST ส่ง `hello` ภายใน `HELLO_TIMEOUT` (5 s) มิฉะนั้นผู้รับ MUST ปิดด้วย `4000`
2. ผู้รับตอบ `hello.ack` — ทั้งสองฝ่าย MUST merge clock: `clock = max(clock, remote.clock) + 1`
3. หลัง handshake ทั้งสองฝ่ายทำ **Catch-up** ตาม §10.7 แล้ว flush Outbound Queue (§6.6)
4. ข้อความอื่นใดที่มาก่อน `hello`/`hello.ack` MUST ถูกตอบด้วย `E_MALFORMED` และปิด connection

### 6.4 Heartbeat

| Parameter | Value |
|---|---|
| ทั้งสองฝ่ายส่ง `ping` ทุก | `PING_INTERVAL` = 15 s |
| ถือว่า connection ตายเมื่อไม่ได้รับ **ข้อความใด ๆ** นาน | `PONG_TIMEOUT` = 45 s (= 3 ping ที่หายไป) |
| เมื่อ timeout | ปิด socket (close code `4008`) แล้วเข้าสู่ reconnect backoff |

### 6.5 Reconnect Backoff

- ลำดับ: `1, 2, 4, 8, 16, 30, 30, …` วินาที, แต่ละค่าคูณ jitter สุ่มในช่วง `[0.8, 1.2]`
- Reset backoff เมื่อ `hello.ack` สำเร็จ
- ได้รับ error ที่ `fatal: true` → MUST NOT reconnect อัตโนมัติจนกว่าผู้ใช้จะสั่ง
- เมื่อ connection ปิด MUST ปล่อย socket/timer/subscription ทั้งหมด (NFR-RE03 — Zero Socket Leak)

### 6.6 Outbound Queue

- ต่อ peer: เก็บข้อความที่ส่งไม่ได้ระหว่างออฟไลน์สูงสุด `OUTBOUND_QUEUE_SIZE` = 50 รายการ (เกิน → drop รายการเก่าสุด)
- เมื่อเชื่อมต่อใหม่ MUST flush ตามลำดับเดิม โดยใช้ `msg_id` เดิม (ผู้รับ dedup ได้)
- ข้อความประเภท `ping`/`pong`/`hello*` MUST NOT เข้าคิว

### 6.7 WebSocket Close Codes

| Code | ความหมาย |
|---|---|
| `1000` | ปิดปกติ |
| `4000` | Protocol error (hello timeout, ข้อความผิดลำดับ) |
| `4001` | Duplicate connection (§6.2) |
| `4003` | Not paired / Revoked |
| `4008` | Heartbeat timeout |
| `4009` | Version mismatch |

---

## 7. Control Plane Messages

### 7.1 Message Envelope

ทุกข้อความบน WebSocket MUST อยู่ในรูปนี้:

```json
{
  "v": 1,
  "type": "clipboard.update",
  "msg_id": "6f1c2c1e-6a43-4c4e-9d0c-0b6f3a5b1e27",
  "origin": "550e8400-e29b-41d4-a716-446655440000",
  "clock": 1428,
  "ts": 1757280000000,
  "payload": { }
}
```

| Field | Type | Required | คำอธิบาย |
|---|---|---|---|
| `v` | int | ✅ | Protocol version |
| `type` | string | ✅ | ตาม §7.2 |
| `msg_id` | uuid | ✅ | ไม่ซ้ำต่อข้อความ — ใช้ dedup |
| `origin` | uuid | ✅ | **อุปกรณ์ที่สร้างข้อมูลจริง ไม่ใช่ผู้ส่งต่อ** |
| `clock` | int | ✅ | Lamport logical clock ณ เวลาสร้างข้อความ |
| `ts` | int64 | ✅ | Wall clock — ใช้แสดงผลและวัด latency เท่านั้น **MUST NOT ใช้ตัดสิน ordering** |
| `payload` | object | ✅ | ตาม `type` |

> ⚠️ **`origin` คือหัวใจของ loop prevention** อย่าสับสนกับ transport-level sender

ข้อความที่เกิน `WS_MAX_MESSAGE_SIZE` (64 KiB) MUST ถูกปฏิเสธด้วย `E_PAYLOAD_TOO_LARGE`

### 7.2 Message Type Registry

| Type | Direction | คำอธิบาย | SRS |
|---|---|---|---|
| `hello` | initiator → responder | เปิด session | FR-10 |
| `hello.ack` | responder → initiator | ตอบรับ session | FR-10 |
| `clipboard.update` | bidirectional | อัปเดต clipboard | FR-03A/B, FR-04 |
| `clipboard.clear` | bidirectional | ล้าง clipboard เมื่อ TTL หมด | FR-05 |
| `file.offer` | sender → receiver | เสนอส่งไฟล์ | FR-07 |
| `file.accept` | receiver → sender | ตอบรับ (auto หรือผู้ใช้กด) | FR-08, SF-07 |
| `file.reject` | receiver → sender | ปฏิเสธ | FR-08 |
| `file.progress` | receiver → sender | ความคืบหน้าที่เขียนลงดิสก์แล้ว | FR-07 |
| `file.complete` | receiver → sender | transfer เข้าสถานะสุดท้าย | FR-08 |
| `file.cancel` | bidirectional | ยกเลิก transfer | FR-07 |
| `device.revoked` | revoker → revoked | แจ้งว่าถูกเพิกถอน | FR-11 |
| `ping` / `pong` | bidirectional | heartbeat | FR-10 |
| `error` | bidirectional | แจ้งข้อผิดพลาด | — |

### 7.3 กฎทั่วไป

- ข้อความทุกประเภทยกเว้น `error` MUST มาจาก peer ที่ผ่าน `hello` แล้ว
- ผู้รับ MUST dedup ด้วย `msg_id` (LRU `SEEN_MSG_CACHE` = 200 entries ต่อเครื่อง)
- ผู้รับ MUST merge Lamport clock ทุกครั้งที่ได้รับข้อความ (ทุก type)

### 7.4 Payload Schemas

#### 7.4.1 `hello` / `hello.ack`

```json
{
  "device_id": "550e8400-e29b-41d4-a716-446655440000",
  "name": "MacBook Pro ของเจ",
  "os": "macos",
  "tier": 1,
  "app_version": "1.0.0",
  "capabilities": ["clip.text", "clip.image", "clip.push", "file", "file.resume"],
  "clock": 1428,
  "clip_head": { "clock": 1420, "origin": "550e8400-...", "hash": "9f86d0...", "msg_id": "6f1c2c1e-..." }
}
```

| Capability | ความหมาย |
|---|---|
| `clip.text` | รับ/ส่ง `text/plain`, `text/uri-list` |
| `clip.image` | รับ/ส่ง `image/png`, `image/jpeg` |
| `clip.push` | เขียน clipboard ได้ทันทีเมื่อได้รับ (Tier 1, Tier 2) — Tier 3 MUST NOT ประกาศ |
| `file` | รับไฟล์ได้ |
| `file.resume` | รองรับ resume (§12.4) |

- `device_id` MUST ตรงกับ CN ของ client/server cert และ record ใน Trusted Store มิฉะนั้น → `E_NOT_PAIRED`
- `clip_head` = รายการล่าสุดที่ยอมรับ (null ถ้าไม่มี) — ใช้ใน Catch-up §10.7

#### 7.4.2 `clipboard.update`

```json
{
  "content_type": "text/plain",
  "hash": "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08",
  "size": 11,
  "is_concealed": false,
  "ttl_seconds": null,
  "inline": "SGVsbG8gV29ybGQ=",
  "blob_id": null,
  "meta": { "width": null, "height": null, "dpi": null }
}
```

| Field | Type | คำอธิบาย |
|---|---|---|
| `content_type` | string | `text/plain` \| `text/uri-list` \| `image/png` \| `image/jpeg` (SRS §1.3.1) |
| `hash` | hex | SHA-256 ของ **raw content ก่อน base64** (text = UTF-8 bytes) |
| `size` | int | ขนาด raw content (bytes), MUST ≤ `CLIPBOARD_MAX_SIZE` |
| `is_concealed` | bool | MUST เป็น `false` เสมอใน v1 (ดูกฎข้อ 3) |
| `ttl_seconds` | int? | null = ไม่หมดอายุ; ถ้ามีค่า MUST อยู่ในช่วง 5–3600 |
| `inline` | string? | Base64 ของ raw content |
| `blob_id` | uuid? | อ้างอิง blob บน Data Plane (§9.3) |
| `meta` | object | `width`/`height` เป็น pixel, `dpi` เป็นตัวเลข (เช่น 72, 144) — ใช้กับรูปเท่านั้น |

**กฎเหล็ก:**
1. `size ≤ CLIPBOARD_INLINE_THRESHOLD` (32,768) → MUST ใช้ `inline`, `blob_id` MUST เป็น null
2. `size > CLIPBOARD_INLINE_THRESHOLD` → MUST ใช้ `blob_id`, `inline` MUST เป็น null
3. Concealed content (§10.4) → **ผู้ส่ง MUST NOT สร้างข้อความนี้เลย** (field มีไว้สำหรับ opt-in ในอนาคต — ผู้รับที่เจอ `true` MUST ทิ้ง)

#### 7.4.3 `clipboard.clear`

```json
{ "hash": "9f86d081...", "reason": "ttl_expired" }
```
ผู้รับ MUST ล้าง clipboard ของตัวเอง **เฉพาะเมื่อ** hash ของข้อมูลบน clipboard ปัจจุบันเท่ากับ `hash` (FR-05 Business Rule)

#### 7.4.4 `file.offer`

```json
{
  "transfer_id": "c3d4e5f6-7a8b-4c9d-8e0f-1a2b3c4d5e6f",
  "items": [
    {
      "item_id": "i1",
      "path": "Photos/vacation.jpg",
      "size": 2458123,
      "sha256": "d2a84f4b8b650937ec8f73cd8be2c74add5a911ba64df27458ed8229da804a26",
      "mime": "image/jpeg",
      "modified_at": 1757200000000
    }
  ],
  "manifest": false,
  "total_size": 2458123,
  "total_count": 1
}
```

- ถ้า `items` encode แล้วทำให้ข้อความเกิน 48 KiB ผู้ส่ง MUST ตั้ง `items: null`, `manifest: true` และผู้รับดึงรายการผ่าน `GET /api/v1/file/{transfer_id}/manifest` จาก**ผู้ส่ง** (§9.6)
- `item_id` MUST ไม่ซ้ำภายใน transfer, ≤ 64 ASCII chars `[A-Za-z0-9_-]`
- `path` MUST ผ่านกฎ §17.3 (ผู้ส่งตรวจก่อนส่ง และ**ผู้รับ MUST ตรวจซ้ำเสมอ — ห้ามเชื่อผู้ส่ง**)
- `total_count` ≤ `MAX_ITEMS_PER_TRANSFER` (10,000)

#### 7.4.5 `file.accept` / `file.reject`

```json
{ "transfer_id": "c3d4e5f6-...", "accepted_items": ["i1"], "auto": true }
```
```json
{ "transfer_id": "c3d4e5f6-...", "reason": "user_declined" }
```

Reason ที่อนุญาต: `user_declined` | `insufficient_space` | `unsupported_type` | `too_large` | `timeout` | `busy` | `invalid_path`

- `auto: true` = ตอบรับอัตโนมัติจาก Auto-Accept (SF-07)
- ถ้า Auto-Accept ปิด และผู้ใช้ไม่ตอบภายใน `OFFER_TIMEOUT` (60 s) → MUST ส่ง `file.reject` reason `timeout`

#### 7.4.6 `file.progress`

```json
{ "transfer_id": "...", "item_id": "i1", "bytes_received": 1048576, "total": 2458123 }
```
ผู้รับ SHOULD ส่งเมื่อครบ 5% หรือผ่านไป 500 ms แล้วแต่อย่างใดถึงก่อน แต่ MUST NOT ถี่กว่า 1 ครั้ง / 500 ms ต่อ item

#### 7.4.7 `file.complete`

```json
{
  "transfer_id": "...",
  "state": "complete",
  "items": [ { "item_id": "i1", "ok": true, "error": null } ]
}
```
`state`: `complete` | `partial` | `failed` | `cancelled`

#### 7.4.8 `file.cancel`

```json
{ "transfer_id": "...", "reason": "user_cancelled" }
```
ผู้รับ MUST หยุดเขียน ลบ `.part` + sidecar ของ transfer นั้นทันที

#### 7.4.9 `device.revoked`

```json
{ "device_id": "<id ของผู้เพิกถอน>", "reason": "user_revoked" }
```

#### 7.4.10 `ping` / `pong`

```json
{ "seq": 42 }
```
`pong.seq` MUST เท่ากับ `ping.seq` ที่ตอบ

#### 7.4.11 `error`

```json
{ "code": "E_VERSION_MISMATCH", "message": "peer requires protocol v2", "fatal": true, "ref_msg_id": null }
```
`message` MUST NOT มีเนื้อหา clipboard, path เต็ม หรือข้อมูลลับ

---

## 8. Error Code Registry

| Code | HTTP | Fatal | ความหมาย |
|---|---|---|---|
| `E_VERSION_MISMATCH` | 400 | ✅ | protocol version ไม่ตรง |
| `E_NOT_PAIRED` | 403 | ✅ | fingerprint ไม่อยู่ใน Trusted Store (รวมถึงหลังถูก revoke — FR-11) |
| `E_REVOKED` | 403 | ✅ | ใช้เป็น reason ประกอบ `device.revoked` เท่านั้น |
| `E_MALFORMED` | 400 | ⬜ | JSON parse ไม่ได้ / field ขาด / type ผิด / magic bytes ผิด |
| `E_PAYLOAD_TOO_LARGE` | 413 | ⬜ | ข้อความ WS เกิน 64 KiB หรือ clipboard เกิน `CLIPBOARD_MAX_SIZE` |
| `E_RATE_LIMITED` | 429 | ⬜ | เกิน rate limit |
| `E_PAIR_LOCKED` | 429 | ⬜ | ถูก lock จาก SAS/nonce ผิด 3 ครั้ง |
| `E_PAIRING_INVALID` | 401 | ⬜ | ไม่มี session / session ถูกใช้แล้ว / nonce ไม่ตรง / fp ไม่ตรงกับ cert |
| `E_NONCE_EXPIRED` | 410 | ⬜ | QR/PIN หมดอายุ |
| `E_SAS_FAILED` | 401 | ✅ | ผู้ใช้ยืนยันว่า SAS ไม่ตรงกัน |
| `E_UNKNOWN_TRANSFER` | 404 | ⬜ | ไม่รู้จัก `transfer_id`/`item_id` |
| `E_OFFSET_MISMATCH` | 409 | ⬜ | `X-Offset` ไม่ตรงกับ offset ปัจจุบันของผู้รับ |
| `E_CHECKSUM_MISMATCH` | 422 | ⬜ | SHA-256 ไม่ตรง |
| `E_DISK_FULL` | 507 | ⬜ | พื้นที่ดิสก์ไม่พอ |
| `E_INVALID_PATH` | 400 | ⬜ | path traversal / ชื่อไฟล์ผิดกฎ §17.3 |
| `E_BLOB_EXPIRED` | 410 | ⬜ | blob หมดอายุ |
| `E_UNSUPPORTED_TYPE` | 415 | ⬜ | content type ไม่รองรับ หรือผู้ใช้ปิดการซิงก์ type นั้น |
| `E_INTERNAL` | 500 | ⬜ | ข้อผิดพลาดภายใน |

**กฎ:** เมื่อได้รับ error ที่ `fatal: true` ผู้รับ MUST ปิด connection และ MUST NOT reconnect อัตโนมัติจนกว่าผู้ใช้จะสั่ง

HTTP error response body MUST อยู่ในรูป:
```json
{ "error": { "code": "E_INVALID_PATH", "message": "path component '..' not allowed" } }
```

---

## 9. Data Plane — HTTP Endpoints

### 9.1 Endpoint Summary

| Method | Path | Auth | คำอธิบาย | SRS |
|---|---|---|---|---|
| `POST` | `/api/v1/pair` | mTLS (unpinned) + RateLimit | เริ่มจับคู่ | FR-02 |
| `POST` | `/api/v1/pair/confirm` | mTLS (unpinned) + RateLimit | ยืนยันผล SAS | FR-02 |
| `GET` | `/api/v1/info` | Pinned | ข้อมูลอุปกรณ์ (`hello` payload ไม่รวม `clip_head`) | — |
| `GET` | `/api/v1/blob/{blob_id}` | Pinned | ดึง clipboard blob | FR-04 |
| `POST` | `/api/v1/clipboard` | Pinned | One-shot clipboard push (Tier 2/3) | FR-03B, FR-03C |
| `GET` | `/api/v1/clipboard/latest` | Pinned | ดึงรายการ clipboard ล่าสุด (Catch-up) | FR-03C, FR-10 |
| `GET` | `/api/v1/file/{transfer_id}/manifest` | Pinned | รายการไฟล์เมื่อ `manifest: true` (ให้บริการโดยผู้ส่ง) | FR-07 |
| `GET` | `/api/v1/file/{transfer_id}/{item_id}/status` | Pinned | ถาม offset (เริ่มใหม่หรือ resume) | FR-09 |
| `POST` | `/api/v1/file/{transfer_id}/{item_id}` | Pinned | อัปโหลด stream จาก offset | FR-07, FR-08 |
| `POST` | `/api/v1/file/{transfer_id}/finish` | Pinned | ปิด transfer + สรุปผล | FR-08 |
| `DELETE` | `/api/v1/file/{transfer_id}` | Pinned | ยกเลิก + ลบ `.part` | FR-07 |

ทุก response ของ endpoint ที่ Pinned MUST มี `Cache-Control: no-store`

### 9.2 `POST /api/v1/pair` และ `/api/v1/pair/confirm`

**Request — `/pair`**
```json
{
  "v": 1,
  "device_id": "b2c3d4e5-...",
  "name": "Windows PC ที่ทำงาน",
  "os": "windows",
  "tier": 1,
  "fp": "5e884898da28047151d0e56f8dc6292773603d0d6aabbdd62a11ef721d1542d8",
  "nonce": "3q2+7wAAAAAAAAAAAAAAAA==",
  "method": "qr"
}
```

**Response 200**
```json
{ "pair_id": "0b7e…", "device_id": "a1b2c3d4-...", "name": "MacBook Pro ของเจ", "os": "macos", "tier": 1, "fp": "9f86d081..." }
```

**Request — `/pair/confirm`**
```json
{ "pair_id": "0b7e…", "result": "match" }
```

**Response** — `200 {"result":"paired"}` | `401 E_SAS_FAILED` | `410 E_NONCE_EXPIRED` (เกิน `PAIR_CONFIRM_TIMEOUT` = 120 s) | `429`

### 9.3 `GET /api/v1/blob/{blob_id}`

```
HTTP/1.1 200 OK
Content-Type: image/png
Content-Length: 2458123
X-Content-SHA256: d2a84f4b...
Cache-Control: no-store

<binary>
```
- Blob MUST หมดอายุภายใน `BLOB_TTL` (120 s) นับจากประกาศ → `410 E_BLOB_EXPIRED`
- Blob MUST เก็บใน memory หรือ temp file ที่ลบอัตโนมัติ และให้บริการเฉพาะ peer ที่ trusted
- ผู้ให้บริการ blob คือ `origin` (v1 ไม่มี relay)

### 9.4 `POST /api/v1/clipboard` (One-shot push — Tier 2/3)

ใช้โดย Android (QS Tile / Notification / Share Sheet เมื่อยังไม่มี WS) และ iOS Share Extension / Widget / Shortcuts ที่เปิด TLS socket สั้น ๆ ส่งแล้วปิด (FR-03C)

```
POST /api/v1/clipboard HTTP/1.1
Content-Type: text/plain; charset=utf-8 | text/uri-list | image/png | image/jpeg
Content-Length: 11
X-DropClip-Msg-Id: 6f1c2c1e-6a43-4c4e-9d0c-0b6f3a5b1e27
X-DropClip-Origin: <device_id ของผู้ส่ง>
X-DropClip-Clock: 1430
X-DropClip-Ts: 1757280000000
X-DropClip-TTL: 60                      (optional)
X-Content-SHA256: a591a6d4...

Hello World
```

- Body คือ raw content (ไม่ base64) — ผู้ส่ง SHOULD stream จากไฟล์เพื่อคุม memory (NFR-R03B)
- `Content-Length` MUST ≤ `CLIPBOARD_MAX_SIZE`
- ผู้รับ MUST ประมวลผลเหมือน `clipboard.update` ขาเข้าทุกประการ (§10.3) รวมถึง dedup และ LWW
- **Response 200:** `{ "applied": true, "clock": 1432 }` — ผู้ส่ง MUST merge `clock`
- ผู้รับที่เป็น Tier 1 SHOULD broadcast ต่อไปยัง peer อื่นของตัวเอง? **ไม่ — v1 ไม่มี relay** ผู้ส่ง (มือถือ) MUST ส่งตรงไปยังทุก desktop ที่เลือก/ออนไลน์

### 9.5 `GET /api/v1/clipboard/latest`

- `200` + headers ชุดเดียวกับ §9.4 + raw body ของ `clip_head` ปัจจุบัน
- `204` เมื่อไม่มีรายการ, รายการหมด TTL แล้ว หรือผู้ใช้ปิดการซิงก์
- Concealed content ไม่เคยถูกเก็บ จึงไม่มีทางถูกส่งผ่าน endpoint นี้

### 9.6 `GET /api/v1/file/{transfer_id}/manifest`

`200` → `{ "transfer_id": "...", "items": [ ...รูปแบบเดียวกับ file.offer... ] }` — ผู้ส่งให้บริการจนกว่า transfer จะจบหรือ 10 นาที

### 9.7 `GET /api/v1/file/{transfer_id}/{item_id}/status`

```json
{ "offset": 3145728, "state": "in_progress", "last_chunk_sha256": "b94d27b9..." }
```

| Field | คำอธิบาย |
|---|---|
| `offset` | จำนวน byte ที่ persist แล้ว — **MUST ปัดลงให้ลงขอบ `FILE_CHUNK_SIZE`** (ผู้รับ truncate `.part` ให้ตรง) ยกเว้นเมื่อ `offset == size` |
| `state` | `pending` \| `in_progress` \| `verifying` \| `complete` \| `failed` |
| `last_chunk_sha256` | SHA-256 ของ chunk สุดท้าย `[offset − CHUNK, offset)`; null เมื่อ `offset == 0` |

### 9.8 `POST /api/v1/file/{transfer_id}/{item_id}`

**Request Headers**
```
Content-Type: application/octet-stream
Transfer-Encoding: chunked
X-Offset: 3145728
```

- `X-Offset` MUST เท่ากับ `0` (เริ่มใหม่ — ผู้รับ truncate `.part` เป็น 0) หรือเท่ากับ `offset` ปัจจุบันของผู้รับ มิฉะนั้น `409 E_OFFSET_MISMATCH`
- Body คือ bytes จาก `X-Offset` ถึงท้ายไฟล์

**Response 200**
```json
{ "received_bytes": 2458123, "state": "complete", "saved_path": "Photos/vacation.jpg" }
```
`saved_path` เป็น path **relative ต่อ destination folder** เท่านั้น (ไม่เปิดเผย absolute path)

**Response 422** → `E_CHECKSUM_MISMATCH` (ผู้รับลบ `.part` แล้ว) | **507** → `E_DISK_FULL` | **400** → `E_INVALID_PATH`

> ⚠️ **ผู้รับ MUST เขียนแบบ stream ลง `.part` เท่านั้น** — MUST NOT buffer ทั้งไฟล์ใน memory; peak memory MUST คงที่ไม่ว่าไฟล์ใหญ่เท่าไร (NFR-R01)

```dart
// ✅ ถูกต้อง
await for (final chunk in request.read()) {
  hasher.add(chunk);
  sink.add(chunk);
}

// ❌ ผิด — reject PR ทันที
final bytes = await request.readAsBytes();
```

### 9.9 `POST /api/v1/file/{transfer_id}/finish`

**Request** `{}` — **Response 200**
```json
{ "state": "complete", "items": [ { "item_id": "i1", "ok": true, "saved_path": "Photos/vacation.jpg" } ] }
```
ผู้รับ MUST แสดง System Notification (FR-08 step 6) และส่ง `file.complete` ผ่าน WS

### 9.10 `DELETE /api/v1/file/{transfer_id}`

`204` — ลบ `.part` และ sidecar ทั้งหมดของ transfer

---

## 10. Clipboard Sync Algorithm (Normative)

> **นี่คือส่วนที่พังง่ายที่สุดของทั้งระบบ — อ่านให้เข้าใจก่อนแตะโค้ด**

### 10.1 State ต่ออุปกรณ์

| ตัวแปร | Type | Persist? | คำอธิบาย |
|---|---|---|---|
| `_clock` | int | ✅ (`state.json`) | Lamport clock — MUST persist ทุกครั้งที่ `++` จาก local event; merge จาก remote persist แบบ debounce ≤ 1 s |
| `_head` | ClipEntry? | ⬜ | รายการล่าสุดที่ยอมรับ `{clock, origin, hash, msg_id, content_type, ttl, data}` |
| `_lastAppliedHash` | hex? | ⬜ | hash ของข้อมูลที่ DropClip เพิ่งเขียนลง OS clipboard |
| `_suppressUntil` | DateTime | ⬜ | หมดเวลา suppression window |
| `_seenMsgIds` | LRU(200) | ⬜ | dedup |
| `_history` | Ring(20) | ⬜ | Catch-up queue (E-04) |

> **ทำไม `_clock` ต้อง persist:** ถ้ารีสตาร์ตแล้วเริ่มที่ 0 การ copy ครั้งแรกจะได้ clock ต่ำกว่า `_head` ของ peer และถูก LWW ทิ้งเงียบ ๆ

### 10.2 Outbound — เมื่อ clipboard ในเครื่องเปลี่ยน (FR-03A, FR-04 ขาส่ง)

```dart
void onLocalClipboardChanged(ClipboardEvent e) {
  // Step 0: ผู้ใช้ปิดซิงก์ หรือ type นี้ไม่อยู่ใน config.sync_types → จบ
  if (!config.clipboardSyncEnabled || !config.allows(e.contentType)) return;

  // Step 1: Sensitive filter (FR-05) — ตรวจก่อนอ่านเนื้อหาเสมอ
  if (e.isConcealed) {
    log.info('clipboard.blocked_concealed', {'type': e.contentType}); // ห้าม log เนื้อหา
    return;
  }

  final raw = FormatNormalizer.toWire(e);          // §11 — ได้ text UTF-8 / PNG / JPEG
  final hash = sha256(raw);

  // Step 2: Suppression — กันการยิงกลับข้อมูลที่ DropClip เพิ่งเขียนเอง
  if (now().isBefore(_suppressUntil) && hash == _lastAppliedHash) {
    log.debug('clipboard.suppressed_echo');
    return;
  }

  // Step 3: Size routing
  if (raw.length > CLIPBOARD_MAX_SIZE) { log.warn('clipboard.too_large'); return; }
  final useBlob = raw.length > CLIPBOARD_INLINE_THRESHOLD;
  final blobId = useBlob ? _blobStore.put(raw, ttl: BLOB_TTL) : null;

  // Step 4: Clock แล้ว broadcast ไปทุก peer ที่ CONNECTED (offline → Outbound Queue)
  _clock++; persistClock();
  final env = Envelope(type: 'clipboard.update', origin: myId, clock: _clock, payload: ClipboardPayload(
    contentType: e.contentType, hash: hash, size: raw.length, isConcealed: false,
    ttlSeconds: config.clipboardTtlSeconds,
    inline: useBlob ? null : base64(raw), blobId: blobId, meta: e.imageMeta,
  ));
  _accept(env, raw);                               // ตั้ง _head + _history
  if (env.payload.ttlSeconds != null) _scheduleClear(hash, env.payload.ttlSeconds!);
  broadcast(env, onlyTo: peers.where((p) => p.supports(e.contentType)));
}
```

### 10.3 Inbound — เมื่อได้รับ `clipboard.update` หรือ `POST /api/v1/clipboard` (FR-04 ขารับ)

```dart
Future<void> onRemoteClipboardUpdate(Envelope env, Peer sender) async {
  // Step 1: Lamport merge — MUST ทำก่อนอย่างอื่นเสมอ
  _clock = max(_clock, env.clock) + 1;

  // Step 2: ทิ้งข้อมูลที่ตัวเองสร้าง (กัน loop)
  if (env.origin == myId) return;

  // Step 3: Dedup ด้วย msg_id (กันส่งซ้ำจาก reconnect / outbound queue)
  if (!_seenMsgIds.addIfAbsent(env.msgId)) return;

  // Step 4: Policy — ปิดซิงก์ / type ไม่อนุญาต / concealed → ทิ้ง
  if (!config.clipboardSyncEnabled || !config.allows(env.payload.contentType)) return;
  if (env.payload.isConcealed) return;

  // Step 5: Last-Writer-Wins + deterministic tie-break
  if (_head != null) {
    if (env.clock < _head.clock) return;
    if (env.clock == _head.clock && env.origin.compareTo(_head.origin) < 0) return;
  }

  // Step 6: ได้ raw bytes
  final raw = env.payload.blobId != null
      ? await fetchBlob(sender, env.payload.blobId!)        // GET /api/v1/blob/{id}
      : base64Decode(env.payload.inline!);

  // Step 7: Integrity + validation (magic bytes ของรูป — §11.3)
  if (sha256(raw) != env.payload.hash) return sendError(sender, 'E_CHECKSUM_MISMATCH', env);
  if (!FormatNormalizer.validate(raw, env.payload.contentType)) return sendError(sender, 'E_MALFORMED', env);

  _accept(env, raw);

  // Step 8: Tier 3 (iOS) — เก็บไว้รอ foreground/Widget เท่านั้น (§10.6)
  if (!myCapabilities.contains('clip.push')) return;

  // Step 9: ตั้ง suppression ก่อนเขียน — ลำดับสำคัญมาก
  _lastAppliedHash = env.payload.hash;
  _suppressUntil = now().add(SUPPRESSION_WINDOW);           // 800 ms

  // Step 10: แปลงเป็นรูปแบบ native แล้วเขียนลง OS clipboard (retry ตาม §14.1)
  await clipboard.write(FormatNormalizer.toNative(raw, env.payload.contentType, myOs));

  // Step 11: TTL
  if (env.payload.ttlSeconds != null) _scheduleClear(env.payload.hash, env.payload.ttlSeconds!);
}
```

### 10.4 Sensitive Content Filter (FR-05)

| OS | สัญญาณ concealed | การกระทำของ Native layer |
|---|---|---|
| macOS | Pasteboard type `org.nspasteboard.ConcealedType` (และ `org.nspasteboard.TransientType`) | ส่ง event `is_concealed: true` **โดยไม่อ่านเนื้อหา** |
| Windows | Clipboard format `ExcludeClipboardContentFromMonitorProcessing` หรือ `CanIncludeInClipboardHistory` = 0 | เช่นเดียวกัน |
| Android | `ClipDescription.getExtras()` มี `android.content.extra.IS_SENSITIVE` = true | ยกเลิกการส่งออก |
| iOS | — (ส่งออกเฉพาะเมื่อผู้ใช้สั่งชัดเจนผ่าน Share Extension) | ไม่เกี่ยว |

- Log ได้เฉพาะ `{type, size}` — MUST NOT log เนื้อหา/hash ของข้อมูล concealed
- Concealed content MUST NOT ออกจากเครื่องต้นทาง **100%** (NFR-S04)

### 10.5 ทำไมต้องมีทั้ง hash และ time window

| กลไก | ป้องกัน | ข้อเสียถ้าใช้เดี่ยว ๆ |
|---|---|---|
| Hash เดี่ยว | echo ธรรมดา | ผู้ใช้ copy ข้อความเดิมซ้ำโดยเจตนา → ถูกกรองทิ้งผิด ๆ |
| Time window เดี่ยว | echo ที่มาช้า | ผู้ใช้ copy ของใหม่ในช่วง window → ถูกบล็อกผิด ๆ |
| **hash + window** | ✅ ทั้งสองกรณี | — |

macOS ใช้ `changeCount` polling (200–2,000 ms) จึงเห็นการเขียนของเราเองช้า ต้องมี window; และผู้ใช้อาจ copy ข้อความเดิมซ้ำโดยตั้งใจ จึงใช้ hash อย่างเดียวไม่ได้

### 10.6 Tier-specific Behaviour

| Tier | Outbound | Inbound |
|---|---|---|
| **1** | Native Watcher → §10.2 อัตโนมัติ | §10.3 → เขียน OS clipboard ทันที |
| **2 Android** | ผู้ใช้แตะ QS Tile / ปุ่ม "Send Clipboard" / Share Sheet → เปิด Transparent Activity (Transient Focus) → `getPrimaryClip()` → ตรวจ `IS_SENSITIVE` → ส่ง `clipboard.update` ผ่าน WS (ถ้า CONNECTED) หรือ `POST /api/v1/clipboard` | Foreground Service รับ WS → `setPrimaryClip()` → Silent notification "คัดลอกจาก [Device Name] แล้ว" |
| **3 iOS** | Share Extension / Widget / Action Button / Shortcuts → `POST /api/v1/clipboard` ไปยัง desktop ที่เลือก แล้วปิด connection | เก็บใน `_head` ขณะแอป CONNECTED; เมื่อแอปเข้าสู่ foreground หรือผู้ใช้แตะ Widget → `GET /api/v1/clipboard/latest` → เขียน `UIPasteboard.general` (ถ้า iOS แสดง Paste Permission แล้วผู้ใช้ปฏิเสธ → แสดงคำแนะนำ ไม่ crash) |

### 10.7 Catch-up (FR-10 step 4)

- `_history` เก็บ 20 รายการล่าสุด (E-04) ใน memory เท่านั้น
- หลัง `hello`/`hello.ack` แต่ละฝ่ายเทียบ `clip_head` ของตัวเองกับของอีกฝ่ายตามกฎ LWW (§10.3 step 5)
- ฝ่ายที่ head ใหม่กว่า MUST ส่ง **envelope เดิมของ head 1 รายการ** (`msg_id`, `origin`, `clock` เดิม) — ไม่ส่งทั้ง 20
- รายการที่ TTL หมดแล้ว MUST NOT ถูกส่ง
- **Partition semantics:** event ที่เกิดระหว่าง network partition ถือเป็น concurrent — ทุกเครื่อง converge ไปค่าเดียวกันตาม `(clock, origin)` แต่ไม่รับประกันว่าเป็นค่าที่ "ล่าสุดตามนาฬิกาจริง"

### 10.8 TTL Clear (FR-05)

```dart
void _scheduleClear(String hash, int ttlSeconds) {
  final token = clipboard.changeToken();                  // §14.1
  Timer(Duration(seconds: ttlSeconds), () async {
    // MUST ล้างเฉพาะเมื่อ clipboard ยังเป็นข้อมูลเดิม — ถ้าผู้ใช้ copy ทับแล้ว MUST NOT แตะ
    if (clipboard.changeToken() == token && await clipboard.currentHash() == hash) {
      await clipboard.clear();
      if (_head?.origin == myId) broadcast(Envelope(type: 'clipboard.clear',
          payload: {'hash': hash, 'reason': 'ttl_expired'}));
    }
  });
}
```

---

## 11. Image Normalization — Wire Rules (FR-06)

### 11.1 Wire Formats

- รูปภาพบน wire MUST เป็น `image/png` (canonical)
- `image/jpeg` อนุญาต **เฉพาะ** เมื่อ clipboard ต้นทางถือ JPEG bytes ต้นฉบับอยู่แล้ว (ส่งต่อโดยไม่ re-encode — UR-03)
- Pixel dimensions MUST คงเดิมทุก pixel (ห้าม downscale — Retina screenshot ต้องได้ pixel เต็ม)
- DPI MUST ถูกเก็บใน `meta.dpi` และใน PNG `pHYs` chunk

### 11.2 Conversion Matrix (Normative)

| ต้นทาง (native) | ไป wire | กฎ |
|---|---|---|
| macOS `public.tiff` (multi-representation) | PNG | เลือก representation ที่ pixel มากที่สุด |
| macOS `public.png` | PNG | ส่งตรง |
| Windows `CF_DIB` | PNG | BGR(A) → RGBA, bottom-up → top-down (ถ้า `biHeight > 0`), ไม่มี alpha → alpha = 255 |
| Windows `CF_DIBV5` | PNG | อ่าน `bV5AlphaMask`/`BI_BITFIELDS` เพื่อคง alpha |
| Windows `PNG` (registered format) | PNG | ส่งตรง (มีลำดับความสำคัญเหนือ DIB) |
| Android/iOS image | PNG/JPEG | ส่งตรงตาม MIME ต้นฉบับ |

| Wire | ไป native ปลายทาง | กฎ |
|---|---|---|
| PNG → Windows | **ทั้ง** registered `PNG` format **และ** `CF_DIBV5` (32bpp, BI_BITFIELDS, alpha mask) พร้อมกัน |
| PNG → macOS | `public.png` และ SHOULD `public.tiff` |
| PNG/JPEG → Android | ไฟล์ชั่วคราวผ่าน `FileProvider` → `ClipData.newUri` |
| PNG/JPEG → iOS | `UIPasteboard.general.image` / `setData(forPasteboardType:)` |

### 11.3 Validation

- Magic bytes: PNG `89 50 4E 47 0D 0A 1A 0A`, JPEG `FF D8 FF` — ไม่ตรง → `E_MALFORMED` แล้วทิ้ง
- ขนาดภาพ MUST ≤ `IMAGE_MAX_PIXELS` (64,000,000 px ≈ 8000×8000) — กัน decompression bomb
- Malformed input MUST throw `NormalizationException` — ห้าม crash ห้าม OOM

---

## 12. File Transfer — Normative Flow (FR-07, FR-08, FR-09)

### 12.1 Sequence

```
Sender                                                Receiver
  │── file.offer (WS) ─────────────────────────────────▶│ ตรวจ path ทุก item (§17.3), ตรวจพื้นที่ดิสก์
  │                                                     │ auto_accept && trusted → accept ทันที (SF-07)
  │◀──────────────────────────── file.accept / reject ──│ ไม่ auto → ถามผู้ใช้ (timeout 60 s)
  │ (ต่อ item ตามลำดับ)                                  │
  │── GET  /file/{t}/{i}/status ───────────────────────▶│ offset = 0 (หรือค่าเดิมถ้า resume)
  │── POST /file/{t}/{i}  X-Offset: N  (chunked) ───────▶│ stream → .part + SHA-256 incremental
  │◀──────────────────── file.progress (WS, ≤ 2 Hz) ────│
  │◀─── 200 {state: complete} ──────────────────────────│ SHA ตรง → rename .part → ชื่อจริง
  │── POST /file/{t}/finish ───────────────────────────▶│ notification
  │◀──────────────────────────────── file.complete ─────│
```

### 12.2 Sender Rules (FR-07)

- สำรวจไฟล์/โฟลเดอร์ คำนวณ SHA-256 แบบ streaming ก่อน offer (ไม่โหลดทั้งไฟล์)
- อ่านไฟล์ทีละ `FILE_CHUNK_SIZE` (1 MiB) — **ห้าม `readAsBytes()`**
- แจ้ง progress ไป UI ทุก 500 ms หรือทุก 5%
- ส่งได้เฉพาะ peer ใน Trusted Store
- Items ภายใน transfer เดียวส่งตามลำดับ; สูงสุด `MAX_CONCURRENT_TRANSFERS` = 3 transfer ต่อ peer พร้อมกัน

### 12.3 Receiver Rules (FR-08)

1. ตรวจสิทธิ์ผ่าน pinning → ไม่ผ่าน `403 E_NOT_PAIRED`
2. Sanitize path (§17.3) → ไม่ผ่าน `400 E_INVALID_PATH`
3. ตรวจพื้นที่ว่าง ≥ `total_size` + 64 MiB → ไม่พอ `file.reject insufficient_space` / `507 E_DISK_FULL`
4. เขียนลง `<dest>/.dropclip-partial/<transfer_id>/<item_id>.part` พร้อม sidecar `<item_id>.part.json` (§15.5)
5. ครบ `size` → เทียบ SHA-256 → ตรง: rename ไปยัง `<dest>/<path>`; ชื่อชน → เติม ` (1)`, ` (2)`, … ก่อนนามสกุล; ไม่ตรง: ลบ `.part` + `422`
6. แสดง System Notification
7. **Security:** macOS MUST ตั้ง `com.apple.quarantine`; Windows SHOULD เขียน Mark-of-the-Web (`Zone.Identifier`, `ZoneId=3`); **ทุก OS MUST NOT เปิดหรือ execute ไฟล์อัตโนมัติ**
8. มือถือ: รูป/วิดีโอ → `MediaStore` (Android) / `PhotoKit` add-only (iOS); อื่น ๆ → Downloads / Files (SW-03)

### 12.4 Resume Rules (FR-09)

1. เมื่อเชื่อมต่อกลับมา ผู้ส่ง MUST เรียก `GET /status` ของ item ที่ยังไม่ `complete`
2. ผู้รับ truncate `.part` ลงขอบ chunk, **rehash prefix ที่มีอยู่แบบ streaming** เพื่อกู้ hasher state แล้วตอบ `offset` + `last_chunk_sha256`
3. ผู้ส่งคำนวณ SHA-256 ของ chunk เดียวกันจากไฟล์ต้นทาง → ตรง: `POST` ด้วย `X-Offset: offset`; ไม่ตรง: `POST` ด้วย `X-Offset: 0` (เริ่ม item ใหม่)
4. ตรวจ SHA-256 ทั้งไฟล์เป็นขั้นตอนสุดท้ายเสมอ
5. `.part` ที่ค้างเกิน `PARTIAL_RETENTION` (24 ชม.) MUST ถูกลบตอนเปิดแอป

---

## 13. Device Management & Revocation (FR-11)

ลำดับ MUST เป็นดังนี้ และทั้งหมด MUST เสร็จภายใน **1 วินาที** (NFR-S05):

1. ลบ fingerprint ออกจาก Trusted Store **ก่อน** (connection ใหม่จะถูกปฏิเสธทันที)
2. ส่ง `device.revoked` ผ่าน WS แบบ best-effort (รอไม่เกิน 200 ms)
3. ปิดทุก socket/HTTP stream ที่ผูกกับอุปกรณ์นั้น (close code `4003`) และยกเลิก transfer ที่ค้าง
4. ลบ peer ออกจาก Outbound Queue / Catch-up target

ฝั่งที่ได้รับ `device.revoked`:
- SHOULD ลบผู้เพิกถอนออกจาก Trusted Store ของตัวเอง และแจ้งผู้ใช้
- MUST NOT reconnect อัตโนมัติ
- ความพยายามเชื่อมต่อใด ๆ หลังจากนี้ได้รับ `403 E_NOT_PAIRED`

---

## 14. Platform Channel Contract (Dart ↔ Native)

> เป้าหมาย: ให้ทีม Native (Swift / C++ / Kotlin) และทีม Dart Engine พัฒนาขนานกันได้โดยไม่ต้องรอกัน Native code SHOULD ≤ ~500 บรรทัด/แพลตฟอร์ม (ADR-001)

### 14.1 Clipboard — Tier 1 (macOS / Windows)

**MethodChannel `dropclip/clipboard`**

| Method | Args | Returns | หมายเหตุ |
|---|---|---|---|
| `start` | — | `void` | เริ่ม watcher |
| `stop` | — | `void` | |
| `read` | — | `ClipSnapshot?` | อ่านปัจจุบัน (null ถ้าว่างหรือไม่รองรับ) |
| `write` | `{items: [{mime, data}]}` | `{change_token}` | เขียนทุก item ใน transaction เดียว |
| `clear` | — | `void` | |
| `changeToken` | — | `int` | macOS `changeCount` / Windows `GetClipboardSequenceNumber()` |

**EventChannel `dropclip/clipboard/events`** — ส่ง `ClipSnapshot`:
```json
{
  "change_token": 1234,
  "is_concealed": false,
  "items": [ { "mime": "text/plain", "data": "<Uint8List>" } ],
  "ts": 1757280000000
}
```
- เมื่อ `is_concealed: true` → `items` MUST เป็น `[]` (native MUST NOT อ่านเนื้อหา)
- MIME ของ native format: `text/plain` (UTF-8), `text/uri-list`, `image/png`, `image/jpeg`, `image/tiff`, `image/x-win-dib`, `image/x-win-dibv5` — การแปลงเป็นหน้าที่ของ Dart Normalizer (§11) ไม่ใช่ native
- Clipboard ถูก lock โดยแอปอื่น → native MUST retry with backoff 50 → 100 → 200 ms (3 ครั้ง) แล้วโยน `PlatformException(code: 'CLIPBOARD_LOCKED')` — **ห้าม crash** (FR-03A Exception Handling)
- macOS adaptive polling: active (มี input ใน 30 s) = 200 ms, idle = 1,000 ms, screen locked = 2,000 ms — native ตัดสินเอง

### 14.2 Android (Tier 2)

| Channel | Method / Event | คำอธิบาย |
|---|---|---|
| `dropclip/android/service` | `startService`, `stopService`, `isRunning` | Foreground Service (`START_STICKY`, `foregroundServiceType="dataSync"`) |
| `dropclip/android/service` | `requestBatteryExemption` | ขอยกเว้น battery optimization |
| `dropclip/clipboard` | `write`, `clear`, `changeToken` | ใช้ร่วมกับ §14.1 (เขียนได้จาก service) |
| `dropclip/android/events` | `{"action": "send_clipboard", "snapshot": ClipSnapshot}` | มาจาก QS Tile / Notification Action ผ่าน Transient Activity |
| `dropclip/android/events` | `{"action": "share", "uris": [...], "text": ...}` | มาจาก Share Sheet (`ACTION_SEND`, `ACTION_SEND_MULTIPLE`) |
| `dropclip/media` | `saveToMediaStore({path, mime})` | SW-03 |

### 14.3 iOS (Tier 3)

| Component | สัญญา |
|---|---|
| App Group | `group.com.dropclip.shared` — เก็บ `identity.json`, `trusted_devices.json.enc`, `state.json` ร่วมกับ Share Extension |
| Keychain Access Group | `$(TeamID).com.dropclip.shared` — private key + store key |
| Share Extension | Native Swift (ไม่ใช้ Flutter engine เพื่อคุม RAM < 30 MB — NFR-R03B) ใช้ `URLSession` + client cert identity → `POST /api/v1/clipboard` หรือ file transfer |
| `dropclip/ios` channel | `pasteboardWrite`, `pasteboardRead` (เรียกได้เฉพาะ foreground), `savePhoto({path})` (PhotoKit add-only) |
| AppIntents | `SendClipboardIntent`, `PullClipboardIntent` — ใช้ร่วมกับ Widget / Action Button / Shortcuts |

### 14.4 Secure Storage (ทุกแพลตฟอร์ม)

Dart interface ที่ทุกแพลตฟอร์ม MUST implement (`dropclip_core`):
```dart
abstract interface class SecureKeyStore {
  Future<Uint8List?> read(String key);
  Future<void> write(String key, Uint8List value);
  Future<void> delete(String key);
}
// Keys: 'dropclip.identity.ed25519'  (private key)
//       'dropclip.store.key'         (AES-256-GCM key สำหรับ trusted_devices.json.enc)
```

### 14.5 Auto-Start (FR-12)

| OS | กลไก | Launch arg |
|---|---|---|
| macOS | `SMAppService.mainApp.register()` | `--hidden` |
| Windows | `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` → `"<exe>" --hidden` | `--hidden` |

เมื่อเปิดด้วย `--hidden` แอป MUST อยู่ใน Tray/Menubar เท่านั้น ห้ามเปิดหน้าต่างหรือ pop-up (NFR-U03)

---

## 15. Local Persistence Schemas (E-01 … E-06)

### 15.1 ตำแหน่งจัดเก็บ

| OS | Directory |
|---|---|
| macOS | `~/Library/Application Support/DropClip/` |
| Windows | `%APPDATA%\DropClip\` |
| Android | `Context.filesDir/dropclip/` |
| iOS | App Group container `group.com.dropclip.shared/dropclip/` |

### 15.2 `identity.json` (E-01 — ส่วนสาธารณะเท่านั้น)
```json
{ "version": 1, "device_id": "550e8400-...", "name": "MacBook Pro ของเจ", "os": "macos",
  "cert_der": "<base64>", "fp": "9f86d0...", "created_at": 1757280000000 }
```

### 15.3 `trusted_devices.json.enc` (E-02)
ไฟล์เข้ารหัส AES-256-GCM (`nonce(12) ‖ ciphertext ‖ tag(16)`) ด้วย `dropclip.store.key` — plaintext:
```json
{ "version": 1, "devices": [
  { "device_id": "b2c3d4e5-...", "name": "Windows PC", "os": "windows", "tier": 1,
    "fp": "5e8848...", "paired_at": 1757280000000, "last_seen_at": 1757290000000, "status": "active" }
] }
```
`status`: `active` (record ที่ revoke แล้ว MUST ถูกลบทิ้ง ไม่ใช่เปลี่ยนสถานะ)

### 15.4 In-memory Entities

| Entity | Fields |
|---|---|
| E-03 `DiscoveredPeer` | `device_id, name, os, tier, ip, port, fp, cap, trust (trusted/untrusted/identity_changed), state, last_seen_at` |
| E-04 `ClipEntry` | `msg_id, content_type, hash, size, is_concealed, ttl_seconds, data, clock, origin, received_at` |

### 15.5 `<item_id>.part.json` (E-05)
```json
{ "version": 1, "transfer_id": "c3d4e5f6-...", "item_id": "i1", "path": "Photos/vacation.jpg",
  "size": 2458123, "sha256": "d2a84f...", "offset": 2097152, "state": "in_progress",
  "peer_id": "b2c3d4e5-...", "updated_at": 1757280000000 }
```

### 15.6 `config.json` (E-06, FR-12)
```json
{
  "version": 1,
  "device_name": "MacBook Pro ของเจ",
  "auto_accept": true,
  "destination_dir": "~/Downloads/DropClip",
  "clipboard_sync_enabled": true,
  "sync_types": ["text", "url", "image"],
  "clipboard_ttl_seconds": null,
  "auto_start": true,
  "log_level": "info"
}
```
- การเปลี่ยน config MUST มีผลทันทีโดยไม่ต้องรีสตาร์ต (ผ่าน `Stream<Config>`)
- ค่าที่ไม่ถูกต้อง → ใช้ค่า default และ log `warn`

### 15.7 `state.json`
```json
{ "version": 1, "lamport_clock": 1428 }
```

---

## 16. Limits & Constants

| Constant | Value | เหตุผล / SRS |
|---|---|---|
| `PROTOCOL_VERSION` | 1 | — |
| `PORT_RANGE` | 53317–53417 | CI-02 |
| `MDNS_TTL` | 120 s | FR-01 |
| `DISCOVERY_QUERY_INTERVAL` | 10 s | ให้ตรวจ stale 30 s ได้แม่นยำ |
| `DEVICE_STALE_TIMEOUT` | 30 s | FR-01 |
| `DEVICE_REMOVE_TIMEOUT` | 120 s | FR-01, E-03 |
| `PAIR_NONCE_TTL` | 60 s | FR-02 |
| `PAIR_CONFIRM_TIMEOUT` | 120 s | เวลาให้ผู้ใช้เทียบ SAS |
| `PAIR_RATE_LIMIT` | 5 / นาที / IP | FR-02 |
| `PAIR_MAX_FAILURES` / `PAIR_LOCKOUT` | 3 ครั้ง / 5 นาที | FR-02 |
| `WS_MAX_MESSAGE_SIZE` | 65,536 bytes | §2.1 |
| `CLIPBOARD_INLINE_THRESHOLD` | 32,768 bytes | FR-03A, FR-04 |
| `CLIPBOARD_MAX_SIZE` | 33,554,432 bytes (32 MiB) | ใหญ่กว่านี้ให้ส่งเป็นไฟล์ |
| `IMAGE_MAX_PIXELS` | 64,000,000 | กัน decompression bomb |
| `BLOB_TTL` | 120 s | — |
| `SUPPRESSION_WINDOW` | 800 ms | FR-03A, FR-04 (> macOS polling worst case ขณะ active) |
| `SEEN_MSG_CACHE` | 200 entries (LRU) | FR-04 |
| `CATCHUP_QUEUE_SIZE` | 20 entries | E-04 |
| `OUTBOUND_QUEUE_SIZE` | 50 ข้อความ / peer | FR-10 |
| `HELLO_TIMEOUT` | 5 s | — |
| `INITIATOR_GRACE` | 10 s | §6.2 |
| `PING_INTERVAL` / `PONG_TIMEOUT` | 15 s / 45 s | FR-10 |
| `RECONNECT_BACKOFF` | 1, 2, 4, 8, 16, 30 s (cap) × jitter [0.8, 1.2] | FR-10 |
| `MAX_PEERS` | 8 | — |
| `FILE_CHUNK_SIZE` | 1,048,576 bytes (1 MiB) | SF-06 |
| `MAX_CONCURRENT_TRANSFERS` | 3 / peer | — |
| `MAX_ITEMS_PER_TRANSFER` | 10,000 | — |
| `OFFER_TIMEOUT` | 60 s | — |
| `PROGRESS_MIN_INTERVAL` | 500 ms | FR-07 |
| `PARTIAL_RETENTION` | 24 ชม. | E-05 |
| `REVOCATION_DEADLINE` | 1,000 ms | NFR-S05 |
| `CLIPBOARD_LOCK_RETRY` | 3 ครั้ง (50/100/200 ms) | FR-03A |
| `MACOS_POLL_ACTIVE/IDLE/LOCKED` | 200 / 1,000 / 2,000 ms | FR-03A |

---

## 17. Security Considerations

### 17.1 Threat Model

| Attacker | ความสามารถ | การป้องกัน |
|---|---|---|
| **Passive eavesdropper ในวง Wi-Fi** | ดักอ่าน traffic | TLS 1.3 — เห็นแค่ mDNS TXT ที่เป็นข้อมูลสาธารณะ |
| **Active MITM ตอน pairing** | แทรกกลางการแลก fingerprint | SAS 6 หลักที่ผู้ใช้ยืนยันด้วยตาทั้งสองฝั่ง + QR pin |
| **Brute-force PIN** | เดา PIN 6 หลัก | TTL 60 s + 5 req/นาที + lockout 3 ครั้ง + single-use session |
| **Malicious peer ในวงเดียวกัน** | ยิง request เข้ามา | Fingerprint pinning — ไม่ pair = 403 |
| **อุปกรณ์ที่สูญหาย** | มี private key ที่ถูกต้อง | Revocation ภายใน 1 วินาที (§13) |
| **Compromised peer ที่ pair แล้ว** | ส่งไฟล์อันตราย / path traversal / blob ยักษ์ | Path sanitization + quarantine + ไม่ auto-execute + size limits |

### 17.2 ข้อกำหนดบังคับ

- Private key MUST อยู่ใน OS secure storage เท่านั้น (§4.2)
- Log MUST NOT มี private key, certificate DER, PIN, nonce หรือเนื้อหา clipboard (log ได้แค่ type + size; hash ได้เฉพาะข้อมูลที่ไม่ concealed)
- Crash report MUST scrub ข้อมูลข้างต้นทั้งหมด
- ไฟล์ที่รับมา MUST NOT ถูกเปิด/execute อัตโนมัติ; macOS MUST ติด quarantine attribute
- Concealed clipboard content MUST NOT ออกจากเครื่องต้นทาง
- Receiver MUST NOT สร้าง symlink/hardlink จากข้อมูลที่ได้รับ

### 17.3 Path Sanitization (บังคับใช้ทั้งสองฝั่ง — NFR-S03)

**กฎ:** wire path ใช้ `/` เป็นตัวคั่นเท่านั้น แล้วตรวจทีละ component

```dart
String sanitizePath(String input) {
  if (input.isEmpty || utf8.encode(input).length > 4096) throw InvalidPathException('length');
  if (input.contains('\\')) throw InvalidPathException('backslash');            // V6
  if (input.startsWith('/')) throw InvalidPathException('absolute');            // V3
  if (RegExp(r'^[A-Za-z]:').hasMatch(input)) throw InvalidPathException('drive'); // V4
  final parts = input.split('/');
  if (parts.length > 32) throw InvalidPathException('depth');
  for (final c in parts) {
    if (c.isEmpty || c == '.' || c == '..') throw InvalidPathException('component'); // V1, V2, V12
    if (RegExp(r'[\x00-\x1F\x7F]').hasMatch(c)) throw InvalidPathException('control'); // V7, V11
    if (RegExp(r'[<>:"|?*]').hasMatch(c)) throw InvalidPathException('reserved_char'); // V10
    if (c.endsWith('.') || c.endsWith(' ')) throw InvalidPathException('trailing');   // V9
    final stem = c.split('.').first.toUpperCase();
    if (RegExp(r'^(CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])$').hasMatch(stem)) {
      throw InvalidPathException('reserved_name');                                  // V8
    }
    if (utf8.encode(c).length > 255) throw InvalidPathException('component_length'); // V12
  }
  return unorm.nfc(parts.join('/'));
}
// Defense in depth: หลัง join กับ destination root แล้ว canonicalize
// MUST ยืนยันว่า resolved path ยังอยู่ใต้ root (กัน UNC \\server\share — V5 — และ edge case ของ OS)
```

ชุดทดสอบการโจมตี 12 รูปแบบ (NFR-S03) อยู่ที่ §18.6

---

## 18. Conformance Test Vectors

> ทุกแพลตฟอร์ม (Dart, Swift Share Extension, Kotlin) MUST ให้ผลตรงกับค่าเหล่านี้ทุกตัว

### 18.1 SAS — QR mode

```
fp_A   = "0000000000000000000000000000000000000000000000000000000000000000"
fp_B   = "1111111111111111111111111111111111111111111111111111111111111111"
nonce  = base64 "MDEyMzQ1Njc4OWFiY2RlZg=="   (= ASCII "0123456789abcdef", 16 bytes)

sas_input  = UTF8(fp_A) ‖ UTF8(fp_B) ‖ nonce_bytes          (144 bytes; fp_A < fp_B)
sas_hash   = c75a3af628ada8bd606909cf780ee15cec594a2e7c4b4d379bc54ceb1b955bc1
uint32_be  = 0xc75a3af6 = 3344579318
sas        = 3344579318 mod 1000000 = "579318"
```
และ MUST ได้ `"579318"` เมื่อสลับ `fp_A` ↔ `fp_B` (symmetry)

### 18.2 PIN Nonce Derivation — PIN mode

```
pin        = "123456"
SHA-256("dropclip-pin-v1:123456") = eabf2def9324cd6e9cc8613f78d12e822bb6799e6b5de66fd56ba95a71004355
pin_nonce  = first 16 bytes → base64 "6r8t75MkzW6cyGE/eNEugg=="

SAS (fp_A, fp_B จาก 18.1 + pin_nonce):
sas_hash   = 5312c35ac1dda6f4e38cf2053dc936e8a30d66a869636ea0ed5e0bc3cb1421b9
sas        = "738586"
```

### 18.3 Lamport Merge

| ลำดับ | A clock | B clock | เหตุการณ์ |
|---|---|---|---|
| 0 | 0 | 0 | เริ่มต้น |
| 1 | 1 | 0 | A copy → ส่ง clock=1 |
| 2 | 1 | 2 | B รับ → max(0,1)+1 = 2 |
| 3 | 1 | 3 | B copy → ส่ง clock=3 |
| 4 | 4 | 3 | A รับ → max(1,3)+1 = 4 |

### 18.4 Tie-break

```
Event X: {origin: "aaaaaaaa-0000-4000-8000-000000000000", clock: 10}
Event Y: {origin: "bbbbbbbb-0000-4000-8000-000000000000", clock: 10}
ทุกอุปกรณ์ MUST เลือก Y (เพราะ "bbbb…" > "aaaa…") ไม่ว่าจะได้รับในลำดับใด
```

### 18.5 Size Routing Boundary

| raw size (bytes) | ผลลัพธ์ |
|---|---|
| 32,767 | `inline` |
| 32,768 | `inline` |
| 32,769 | `blob_id` |
| 33,554,432 | `blob_id` |
| 33,554,433 | ไม่ส่ง (`E_PAYLOAD_TOO_LARGE` ถ้ามาจาก peer) |

### 18.6 Path Attack Vectors (NFR-S03 — ต้องถูกบล็อกครบ 12/12)

| # | Input | เหตุผลที่ต้องบล็อก |
|---|---|---|
| V1 | `../../etc/passwd` | parent traversal |
| V2 | `photos/../../secret.txt` | traversal ซ่อนกลาง path |
| V3 | `/etc/passwd` | absolute POSIX |
| V4 | `C:/Windows/System32/evil.dll` | drive letter |
| V5 | `//server/share/x` | UNC / empty component |
| V6 | `..\..\Windows\win.ini` | backslash separator |
| V7 | `file\u0000.txt` | null byte injection |
| V8 | `CON`, `con.txt`, `COM1.log`, `LPT9` | Windows reserved names |
| V9 | `report.` / `report ` | trailing dot/space (Windows) |
| V10 | `a:b.txt` (ADS), `a<b>.txt`, `what?.txt` | reserved characters |
| V11 | `bad\u001Bname.txt` | control characters |
| V12 | `./a`, `a//b`, component ยาว 256 bytes | empty/dot/overlong component |

Path ที่ต้อง **ผ่าน**: `Photos/vacation.jpg`, `เอกสาร/รายงาน ฉบับที่ 1.pdf`, `😀/emoji file.png`, `a/b/c/d.txt`, `.hidden`, `name.with.dots.tar.gz`

### 18.7 Reconnect Backoff

| Attempt | Base (s) | ช่วงที่ยอมรับ (s) |
|---|---|---|
| 1 | 1 | 0.8 – 1.2 |
| 2 | 2 | 1.6 – 2.4 |
| 3 | 4 | 3.2 – 4.8 |
| 4 | 8 | 6.4 – 9.6 |
| 5 | 16 | 12.8 – 19.2 |
| ≥ 6 | 30 | 24.0 – 36.0 |

---

## 19. Open Issues & Spikes

| ID | ประเด็น | Owner | Exit |
|---|---|---|---|
| S0.1 | TLS 1.3 + mTLS + Ed25519 self-signed + app-layer pinning บน Dart (macOS/Windows/Android) และ `URLSession` (iOS Share Extension) | LEAD | ADR-006; ถ้าต้องใช้ ECDSA P-256 → SRS Change Request |
| S0.2 | Android 10–14: Transient Activity อ่าน clipboard จาก QS Tile/Notification ได้จริงบน Pixel/Samsung/Xiaomi; iOS Share Extension เปิด TLS + client cert ภายใต้ 30 MB | MOB | ADR-007 |
| OI-1 | iOS: AppIntent จาก Widget เขียน `UIPasteboard` ได้หรือไม่โดยไม่เปิดแอป (iOS 17+) | MOB | ผลของ S0.2 — ถ้าไม่ได้ Widget เปิดแอปแทน |
| OI-2 | ขนาด `CLIPBOARD_MAX_SIZE` 32 MiB เหมาะกับ RAM มือถือหรือไม่ | NET | ผลวัดใน T1.29 |

---

## 20. Change Log

| Version | Date | การเปลี่ยนแปลง |
|---|---|---|
| 1.0 | 2026-09-08 | เวอร์ชันแรก — frozen สำหรับ Phase 1 |
| 2.0 | 2026-10-12 | **Realign กับ SRS-DC-V1.2:** เพิ่ม traceability (§0.2) และ Capability Tiers (§2.2, `tier` ใน TXT/hello); เพิ่ม `port` ใน TXT ตาม FR-01; stale = ทำเครื่องหมายไม่ใช่ซ่อน (§3.5) + trust classification `identity_changed`; กำหนด Topology/Initiator rule/Close codes (§6); แยก WS frame limit 64 KiB ออกจาก inline threshold 32 KiB (แก้ความขัดแย้งเดิมเรื่อง base64 overhead); เพิ่ม PIN pairing mode + `/pair/confirm` + lockout `E_PAIR_LOCKED`/`E_PAIRING_INVALID` และเลิกส่ง SAS ใน response; นิยาม SAS input แบบ byte-exact พร้อม test vector ที่คำนวณแล้ว; เพิ่ม `POST /api/v1/clipboard` และ `GET /api/v1/clipboard/latest` สำหรับ Tier 2/3 (FR-03B/C); ลบ `clipboard.request_blob` (ดึง blob ผ่าน HTTP ตรง); เพิ่ม payload `clipboard.clear`, `file.cancel`, `file.complete`; Data plane เปลี่ยนเป็น `POST` + `X-Offset` ตาม FR-07 พร้อม resume แบบ chunk-aligned + `last_chunk_sha256` (FR-09); เพิ่ม `manifest` สำหรับโฟลเดอร์ใหญ่; persist Lamport clock; Image wire rules (§11); Platform Channel Contract (§14); Persistence Schemas E-01…E-06 (§15); Path sanitization ครบ 12 attack vectors (NFR-S03) |