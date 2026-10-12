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
- **ไม่มี relay ใน v1:** อุปกรณ์ MUST NOT forward ข้อความที่ได้รับจาก peer หนึ่งไปยัง peer อื่น ดังนั้นใน v1 `origin` จะเท่ากับผู้ส่งเสมอ — แต่ผู้รับ MUST ยังคงตรวจ `origin` ตาม §10 (defense-in-depth และรองรับ relay ในอนาคต) — **ข้อยกเว้นเดียว:** `cluster.revocation` และ `revocation.sync` (§13.2) MAY ถูกส่งต่อได้ เพราะ token ลงนามโดย `revoker_id` ต้นทางและผู้รับทุกรายตรวจลายเซ็นเอง

### 2.4 Version Negotiation & Compatibility Policy

- ทุกฝ่าย MUST ประกาศ `v` (เวอร์ชันปัจจุบัน) และ `min_v` (เวอร์ชันต่ำสุดที่ยังรองรับได้) ใน mDNS TXT, ในข้อความ `hello` และใน request body ของ `/api/v1/pair`
- **กลไกการเจรจาเวอร์ชัน (Version Negotiation):**
  $$\text{negotiated\_v} = \min(\text{local.v}, \text{remote.v})$$
  หาก $\text{negotiated\_v} \ge \max(\text{local.min\_v}, \text{remote.min\_v})$ ทั้งสองฝ่ายตกลงสื่อสารด้วย $\text{negotiated\_v}$
- หากไม่มีช่วงเวอร์ชันที่รองรับร่วมกัน ฝ่ายรับ MUST ปิดการเชื่อมต่อด้วย Close Code `4003` พร้อมส่งรหัสข้อผิดพลาด `E_UNSUPPORTED_VERSION` (fatal)
- **Forward Compatibility:** โหนดที่ได้รับฟิลด์ JSON ที่ตนไม่รู้จัก MUST ละเว้นฟิลด์นั้นอย่างปลอดภัยโดยไม่ Crash

---

## 3. Discovery Layer (FR-01)

### 3.1 Service Registration

```
Service Type : _dropclip._tcp.local
Instance Name: <device_id>             (UUID v4 — ไม่ใช้ชื่อเครื่องเพราะอาจซ้ำ/มีอักขระที่ mDNS ไม่รองรับ)
Port (SRV)   : พอร์ตที่ bind ได้จริงในช่วง 53317–53417
Record TTL   : 120 วินาที (MDNS_TTL)
```

> **ข้อกำหนดเฉพาะสำหรับ Windows & Firewall Onboarding:**  
> Windows 10/11 มี mDNS Responder ของระบบ (`dnscache`) ที่เปิดใช้งานพอร์ต UDP 5353 อยู่แล้ว DropClip บน Windows SHOULD ใช้ DNS-SD API ของระบบ (`DnsServiceRegister` / `DnsServiceBrowse`, Windows 10 1809+) ผ่าน plugin (เช่น `bonsoir`) แทนการเปิด UDP 5353 เอง เพราะ Dart บน Windows ไม่รองรับ `reusePort` และการแชร์พอร์ตกับ `dnscache` ไม่เสถียร (ยืนยันผลใน T1.1) และแอปพลิเคชันต้องมีหน้าจอ First-Run Onboarding อธิบายให้ผู้ใช้กด "Allow Access" เมื่อ Windows Defender Firewall แจ้งเตือนในครั้งแรก

### 3.2 TXT Record

| Key | Required | ค่า |
|---|---|---|
| `v` | ✅ | Protocol version ปัจจุบัน — เช่น `"1"` |
| `min_v` | ✅ | Protocol version ต่ำสุดที่ยังรองรับได้ — เช่น `"1"` |
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
min_v=1
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
| Key Algorithm | **ECDSA P-256 (secp256r1 / prime256v1)** — ตาม ADR-006 |
| Signature Scheme | ECDSA with SHA-256 (RFC 5480) |
| Certificate | X.509 v3 self-signed, serial = 16 random bytes (CSPRNG) |
| Subject / Issuer CN | `dropclip-<device_id>` |
| Validity | 10 ปี (Self-signed) |
| Fingerprint (`fp`) | `SHA-256(DER(cert))` lowercase hex (64 ตัวอักษร) |
| Generation | สร้างครั้งแรกใน Secure Storage เท่านั้น — ลบแอป/ติดตั้งใหม่ = identity ใหม่ (ไม่กู้ของเก่า) |

> **เหตุผลในการเลือก ECDSA P-256 แทน Ed25519 (ADR-006):**
> 1. **Android 10–12 Compatibility:** Android Keystore รองรับฮาร์ดแวร์ Keymaster/StrongBox สำหรับ Ed25519 ตั้งแต่ Android 13 (API 33) เท่านั้น ขณะที่ขอบเขตงาน DropClip กำหนดไว้ที่ Android 10+ (API 29+) ซึ่ง ECDSA P-256 รองรับครบถ้วนระดับฮาร์ดแวร์ตั้งแต่ Android 6+
> 2. **iOS/macOS Security.framework:** `Security.framework` ของ Apple ไม่รองรับ Ed25519 ในการสร้าง `SecIdentity` สำหรับ client certificate mTLS ใน `URLSession` ของ Share Extension ทำให้ไม่สามารถทำ mTLS ข้าม process ได้หากใช้ Ed25519
> 3. **BoringSSL / Dart Engine Interop:** Dart `SecureServerSocket` ทำงานร่วมกับ X.509 ECDSA P-256 certificate ได้อย่างสมบูรณ์แบบทั้งบน Client และ Server transport

### 4.2 Private Key Storage (NFR-S02)

| OS | กลไกจัดเก็บกุญแจส่วนตัว |
|---|---|
| macOS | PKCS#8 private key เก็บใน Keychain (`kSecClassGenericPassword`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`) |
| iOS | Keychain พร้อม **Keychain Access Group** (`$(TeamID).com.dropclip.shared`); import เป็น `SecIdentity` (PKCS#12) ใน access group เดียวกันเพื่อให้ Share Extension ใช้กับ `URLSession` ได้ |
| Windows | DPAPI `CryptProtectData` (`CurrentUser` scope) เข้ารหัส PKCS#8 blob บันทึกใน Local AppData |
| Android | AES-256-GCM wrapping key ใน Android Keystore (TEE/StrongBox ถ้ามี) เข้ารหัส PKCS#8 blob ใน app-private storage — รองรับ Android 10 (API 29)+ |

> **ข้อจำกัดที่ยืนยันใน S0.1:** Dart `SecurityContext` ต้องได้ private key เป็น bytes (`usePrivateKeyBytes`) จึงใช้ key แบบ non-exportable (StrongBox / Secure Enclave) เป็น TLS key โดยตรงไม่ได้ — private key ECDSA **ไม่ใช่ hardware-bound** แต่ถูกเข้ารหัสด้วย OS secure storage (envelope encryption) และถอดรหัสใน memory เฉพาะตอนสร้าง `SecurityContext` (ความเสี่ยงคงเหลือ: T-I02)

> **Private key MUST NOT ปรากฏเป็น plaintext บนดิสก์ในทุกกรณี** — มี automated security test (grep หา PEM/DER/`BEGIN PRIVATE KEY` ทั้ง app data directory)

### 4.3 TLS Requirements (NFR-S01)

- MUST ใช้ **TLS 1.3 เท่านั้น** — MUST reject TLS 1.2 และต่ำกว่า (ป้องกัน downgrade attack)
- Cipher suites ที่อนุญาต: `TLS_AES_128_GCM_SHA256`, `TLS_AES_256_GCM_SHA384`, `TLS_CHACHA20_POLY1305_SHA256`
- MUST เป็น **mutual TLS (mTLS)** — server MUST request client certificate ทุก connection
- MUST verify peer ด้วย **SHA-256 fingerprint pinning** ไม่พึ่งพา External CA chain

### 4.4 Pinning Logic

**ฝั่ง Client** — ตรวจ server cert ใน TLS callback:
```dart
bool verifyServer(X509Certificate cert, {String? expectedFp}) {
  final fp = sha256.convert(cert.der).toString();
  if (expectedFp != null) return fp == expectedFp;          // pairing ผ่าน QR / reconnect
  return trustedStore.containsFingerprint(fp);              // connection ปกติ
}
```

**ฝั่ง Server** — ผล S0.1 (Dart 3.13.5): BoringSSL ใน Dart **ตัด handshake ทันทีถ้า client ส่ง cert ที่ไม่อยู่ใน trusted list** จึงตรวจ self-signed cert หลัง handshake อย่างเดียวไม่ได้ ให้ทำดังนี้:
1. Bind ด้วย `requestClientCertificate: true` และ `SecurityContext(withTrustedRoots: false)` ที่ `setTrustedCertificatesBytes()` cert ของ**ทุก peer ใน Trusted Store** — เพิ่มได้ทันทีหลัง bind เมื่อ pair สำเร็จ (ทดสอบแล้ว)
2. ทุก endpoint ยกเว้น pairing MUST ตรวจที่ application layer อีกชั้น เพราะ `SecurityContext` ลบ trust ที่เพิ่มแล้วไม่ได้ — cert ที่ถูก revoke ยังผ่าน handshake ได้จนกว่าจะสร้าง context ใหม่ตอนรีสตาร์ต:
```dart
// ทุก request/upgrade ยกเว้น pairing endpoints
final fp = sha256.convert(request.certificate!.der).toString();
if (!trustedStore.containsFingerprint(fp)) {
  return Response(403, body: errorJson('E_NOT_PAIRED'));     // FR-08 step 1
}
```

> **เหตุผลที่ตรวจที่ application layer:** เพื่อให้ตอบ HTTP 403 + error code ได้ตาม FR-08 และ FR-11 แทนการตัด handshake เงียบ ๆ ซึ่ง debug ยาก

**ข้อยกเว้นเดียว:** `POST /api/v1/pair`, `/pair/confirm` และ `/pair/finalize` รับ connection ที่**ไม่มี** client cert (client ที่ยังไม่ pair MUST NOT ส่ง cert เพราะ handshake จะล้ม) — `fp_B` ถูกผูกกับผู้ใช้ผ่าน commitment + SAS แทน และ B พิสูจน์การครอบครอง private key ครั้งแรกตอนเปิด WS หลัง pair แต่ MUST มี rate limit (§5.6) และ MUST ผ่านกระบวนการ Commit-then-Reveal SAS (§5.4, §5.5)

---

## 5. Pairing Protocol (FR-02)

### 5.1 Pairing Session (ฝั่ง Host)

เมื่อผู้ใช้กด **"เพิ่มอุปกรณ์"** บนเครื่อง Host ระบบ MUST สร้าง pairing session:

| Field | ค่า |
|---|---|
| `nonce_A` | 16 random bytes (CSPRNG) — Host Nonce |
| `pin` | 6 หลักสุ่ม (CSPRNG) `000000–999999` |
| `exp` | `now + PAIR_NONCE_TTL` (60 s) |
| `state` | `open` → `committed` → `paired` \| `failed` \| `expired` |

Host MUST แสดงทั้ง **QR Code และ PIN** บนหน้าจอเดียวกัน (UI-03) และ session เป็นแบบ **single-use** — `/pair` ที่ได้รับ Commitment สำเร็จครั้งแรกทำให้ session เปลี่ยนเป็น `committed` และคำขอจับคู่อื่นจะถูกปฏิเสธทันที

### 5.2 Pairing Modes & Cryptographic Commitment (ADR-009)

เพื่อป้องกันการโจมตี Active MITM Brute-Force Keypair ให้ SAS 6 หลักตรงกัน ระบบใช้สถาปัตยกรรม **Commit-then-Reveal Scheme**:

| Mode | ใช้เมื่อ | ช่องทางส่ง `nonce_A` | กลไก Commitment & การจัดการ Secret |
|---|---|---|---|
| `qr` | มือถือสแกน QR จาก Desktop | **Out-Of-Band (OOB)** ผ่านหน้าจอเท่านั้น — ป้องกันผู้โจมตีบนเครือข่ายดักจับ | Client ส่ง `commitment_B = SHA-256("dropclip-commit-v1:" ‖ nonce_B ‖ fp_B)` ใน `/pair` แล้วเปิดเผย `nonce_B` ใน `/confirm` |
| `pin` | Desktop ↔ Desktop หรือกรอก Manual IP | Host สุ่ม PIN 6 หลักและ $N_A$ แสดงบนหน้าจอ; ผู้ใช้กรอก PIN บน Client | **ห้ามส่ง PIN หรือค่าที่คำนวณจาก PIN (เช่น hash/nonce) บนเครือข่ายเด็ดขาด!** ป้องกันการโจมตี Offline Dictionary Brute-force 10^6 โดย Client ส่งเพียง `commitment_B` ใน `/pair` และเปิดเผย `nonce_B` ใน `/confirm`; จากนั้นทั้งสองฝั่งนำ PIN จากหน้าจอมาผสมเป็น salt คำนวณ SAS: $\text{SAS} = \text{SHA-256}(\text{fp}_{lo} \parallel \text{fp}_{hi} \parallel N_A \parallel N_B \parallel \text{"dropclip-pin-salt-v1:"} \parallel \text{UTF8}(PIN)) \bmod 10^6$ |

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
- `nonce` คือ `nonce_A` ที่ส่งผ่าน Visual Out-of-band Channel เท่านั้น
- Encode เป็น JSON (UTF-8) แล้วสร้าง QR ที่ error correction level **M**

### 5.4 Flow (Commit-then-Reveal)

```
Device A — Host (แสดง QR + PIN)                         Device B — Client (สแกน QR / กรอก PIN)
  │ 1. สร้าง session {nonce_A, pin, exp=+60s}                │
  │ 2. แสดง QR + PIN บนหน้าจอ (OOB) ───────────────────────▶ │
  │                                                          │ 3. Client สุ่ม nonce_B (16 bytes)
  │                                                          │    คำนวณ C_B = SHA-256("dropclip-commit-v1:" ‖ nonce_B ‖ fp_B)
  │                                                          │ 4. TLS 1.3 (server-auth เท่านั้น, B ไม่ส่ง client cert — §4.4)
  │                                                          │    mode=qr: pin server fp = QR.fp
  │◀──────────── 5. POST /api/v1/pair ───────────────────────│
  │   {v, min_v, device_id, name, os, tier, fp,              │
  │    commitment_B, method: "qr" | "pin"}                   │  (ห้ามส่ง PIN หรือ pin_nonce บนสายเด็ดขาด!)
  │ 6. ตรวจ: rate limit, session open, exp > now,            │
  │    บันทึก commitment_B, ปรับ state = committed            │
  │──────────── 7. 200 {pair_id, device_id, name, os, tier, ─▶│
  │                     fp, nonce_A}                         │  (Host ส่ง nonce_A ให้ Client)
  │                                                          │ 8. mode=pin: ตรวจ body.fp == server TLS cert fp
  │                                                          │ 9. Client เปิดเผย nonce_B
  │◀──────────── 10. POST /api/v1/pair/confirm ──────────────│
  │   {pair_id, nonce_B}                                     │
  │ 11. ตรวจสอบ Commitment:                                  │
  │     SHA-256("dropclip-commit-v1:" ‖ nonce_B ‖ fp_B)      │
  │     == commitment_B (ไม่ตรง → 401 E_PAIRING_INVALID)     │
  │ 12. ทั้งสองฝั่งคำนวณ SAS อิสระจาก (§5.5):                │
  │     mode=qr : SAS(fp_A, fp_B, nonce_A, nonce_B)          │
  │     mode=pin: SAS(fp_A, fp_B, nonce_A, nonce_B, PIN)     │
  │     แสดงตัวเลขใหญ่ 6 หลักบนหน้าจอทั้งสองเครื่อง          │
  │          [ผู้ใช้เทียบตัวเลขด้วยตา แล้วกด "ตรงกัน"/"ไม่ตรง" ทั้งสองเครื่อง]   │
  │◀──────────── 13. POST /api/v1/pair/finalize ─────────────│
  │   {pair_id, result: "match" | "mismatch"}                │
  │──────────── 14. 200 {result: "paired"} | 401 E_SAS_FAILED ─▶│
  │ 15. ทั้งคู่บันทึกลง Trusted Store (E-02) เฉพาะเมื่อ "paired" │
  │                                                          │ 16. B เปิด WS ตาม §6 ทันที
```

**กฎเหล็ก:**
- Host MUST NOT ส่งค่า SAS หรือ PIN ใน response ใด ๆ — ทั้งสองฝั่ง MUST คำนวณ SAS เองอย่างอิสระ
- **Zero PIN Exposure on Wire:** ห้ามส่ง PIN, แฮชของ PIN, หรือค่าใด ๆ ที่ Derive มาจาก PIN ผ่านเครือข่ายโดยเด็ดขาด ป้องกันผู้โจมตีที่ดักฟัง TLS ทำ Offline Brute-force 10^6 ค่าได้ทันที
- ผลลัพธ์เป็น `paired` ก็ต่อเมื่อ **ผู้ใช้ทั้งสองฝั่งกดยืนยัน "ตรงกัน"** เท่านั้น
- ถ้าฝั่งใดกด "ไม่ตรง", ค่า Commitment ตรวจสอบไม่ผ่าน, หรือหมดเวลา → ทั้งสองฝั่ง MUST ทำลาย session และ MUST NOT บันทึกอะไรลง Trusted Store
- Host MUST นับกรณี "ไม่ตรง" หรือ commitment ล้มเหลวเป็น failed attempt ของ IP ฝั่ง Client (§5.6)

### 5.5 Short Authentication String (SAS) Calculation

#### 5.5.1 QR Mode SAS
```
fp_lo, fp_hi = sort_ascending([fp_A, fp_B])              // เทียบเป็น string lowercase hex (64 chars)
sas_input    = UTF8(fp_lo) ‖ UTF8(fp_hi) ‖ nonce_A ‖ nonce_B // 64 + 64 + 16 + 16 = 160 bytes
sas_hash     = SHA-256(sas_input)
sas_value    = uint32_big_endian(sas_hash[0..3]) mod 1_000_000
sas_display  = zero-pad 6 หลัก เช่น "042817" (UI MAY แสดงเป็น "042 817")
```

#### 5.5.2 PIN Mode SAS (OOB Salted)
```
fp_lo, fp_hi = sort_ascending([fp_A, fp_B])
pin_salt     = UTF8("dropclip-pin-salt-v1:" ‖ pin.trim())
sas_input    = UTF8(fp_lo) ‖ UTF8(fp_hi) ‖ nonce_A ‖ nonce_B ‖ pin_salt
sas_hash     = SHA-256(sas_input)
sas_value    = uint32_big_endian(sas_hash[0..3]) mod 1_000_000
sas_display  = zero-pad 6 หลัก
```

- `nonce_A` = Host CSPRNG nonce (16 bytes)
- `nonce_B` = Client CSPRNG nonce (16 bytes) ที่ผ่านการ Verify Commitment แล้ว
- `sort_ascending`: รับประกันว่าไม่ว่าจะคำนวณจากฝั่ง Host หรือ Client จะได้ลำดับ bytes ของ input เดียวกัน 100%
- **ระดับความปลอดภัย:** แม้ผู้โจมตี MITM จะดักฟังเครือข่ายได้ แต่ไม่สามารถคำนวณสุ่ม keypair ให้เกิด SAS ชนกันได้อีกต่อไป เพราะ (1) Client ได้ผูกมัดค่า $fp_B$ และ $nonce_B$ ไว้ล่วงหน้าใน Commitment $C_B$ และ (2) ใน PIN Mode ผู้โจมตีไม่ทราบค่า PIN 6 หลักที่แสดงบนหน้าจอจริง จึงไม่สามารถคำนวณหรือปลอมแปลง SAS ได้เลย ($P = 10^{-6}$)

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
2. ผู้รับตอบ `hello.ack` — ทั้งสองฝ่าย MUST merge Hybrid Logical Clock (HLC): `hlc = hlc.merge(remote.hlc)` (§10)
3. หลัง handshake ทั้งสองฝ่ายทำ **Catch-up** ตาม §10.7 แล้ว flush Outbound Queue (§6.6)
4. ข้อความอื่นใดที่มาก่อน `hello`/`hello.ack` MUST ถูกตอบด้วย `E_MALFORMED` และปิด connection

### 6.4 Heartbeat & Authoritative Liveness

| Parameter | Value |
|---|---|
| ทั้งสองฝ่ายส่ง `ping` ทุก | `PING_INTERVAL` = 15 s |
| ถือว่า connection ตายเมื่อไม่ได้รับ **ข้อความใด ๆ** นาน | `PONG_TIMEOUT` = 45 s (= 3 ping ที่หายไป) |
| เมื่อ timeout | ปิด socket (close code `4008`) แล้วเข้าสู่ reconnect backoff |

> **Authoritative Liveness Rule:** สำหรับอุปกรณ์ที่อยู่ในสถานะ `CONNECTED` บน WebSocket ให้ถือเอาสถานะ Heartbeat (`PONG_TIMEOUT` = 45 s) เป็นตัวตัดสินความมีชีวิต (Authoritative Liveness) แต่เพียงผู้เดียว โดยเพิกเฉยต่อสถานะ mDNS Stale 30 s ซึ่งมีไว้สำหรับโหนดที่ยังไม่ได้เชื่อมต่อ (Unconnected Nodes) เท่านั้น

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
| `4003` | Unsupported Version (`E_UNSUPPORTED_VERSION` — ไม่มีช่วงเวอร์ชันร่วมกัน) |
| `4004` | Not paired / Revoked (`E_NOT_PAIRED`) |
| `4008` | Heartbeat timeout |

---

## 7. Control Plane Messages

### 7.1 Message Envelope (ADR-008 — HLC Support)

ทุกข้อความบน WebSocket MUST อยู่ในรูปนี้:

```json
{
  "v": 1,
  "type": "clipboard.update",
  "msg_id": "6f1c2c1e-6a43-4c4e-9d0c-0b6f3a5b1e27",
  "origin": "550e8400-e29b-41d4-a716-446655440000",
  "hlc": {
    "l": 1757280000000,
    "c": 0,
    "d": "550e8400-e29b-41d4-a716-446655440000"
  },
  "ts": 1757280000000,
  "payload": { }
}
```

| Field | Type | Required | คำอธิบาย |
|---|---|---|---|
| `v` | int | ✅ | Protocol version (1) |
| `type` | string | ✅ | ตาม §7.2 |
| `msg_id` | uuid | ✅ | ไม่ซ้ำต่อข้อความ — ใช้ dedup |
| `origin` | uuid | ✅ | **อุปกรณ์ที่สร้างข้อมูลจริง ไม่ใช่ผู้ส่งต่อ** |
| `hlc` | object | ✅ | Hybrid Logical Clock `{ "l": int64, "c": int, "d": string }` ณ เวลาสร้างข้อความ |
| `ts` | int64 | ✅ | Wall clock (ms) — ใช้แสดงผลและวัด latency เท่านั้น **MUST NOT ใช้ตัดสิน ordering** |
| `payload` | object | ✅ | ตาม `type` |

> ⚠️ **`origin` คือหัวใจของ loop prevention** อย่าสับสนกับ transport-level sender

ข้อความที่เกิน `WS_MAX_MESSAGE_SIZE` (64 KiB) บน Control Plane MUST ถูกปฏิเสธด้วย `E_PAYLOAD_TOO_LARGE`

### 7.2 Message Type Registry

| Type | Direction | คำอธิบาย | SRS |
|---|---|---|---|
| `hello` | initiator → responder | เปิด session พร้อมเจรจาเวอร์ชันและ Anti-Entropy hash | FR-10 |
| `hello.ack` | responder → initiator | ตอบรับ session และ HLC sync | FR-10 |
| `clipboard.update` | bidirectional | อัปเดต clipboard (inline $\le$ 32 KiB หรือ blob reference) | FR-03A/B, FR-04 |
| `clipboard.clear` | bidirectional | ล้าง clipboard เมื่อ TTL หมด | FR-05 |
| `file.offer` | sender → receiver | เสนอส่งไฟล์ | FR-07 |
| `file.accept` | receiver → sender | ตอบรับ (auto หรือผู้ใช้กด) | FR-08, SF-07 |
| `file.reject` | receiver → sender | ปฏิเสธ | FR-08 |
| `file.progress` | receiver → sender | ความคืบหน้าที่เขียนลงดิสก์แล้ว | FR-07 |
| `file.complete` | receiver → sender | transfer เข้าสถานะสุดท้าย | FR-08 |
| `file.cancel` | bidirectional | ยกเลิก transfer | FR-07 |
| `device.revoked` | revoker → revoked | แจ้งเตือนเครื่องเป้าหมายว่าถูกเพิกถอน | FR-11 |
| `cluster.revocation` | bidirectional / gossip | กระจายคำสั่งเพิกถอนพร้อมลายเซ็น ECDSA ไปยังทุก Peer | FR-11, SF-08 |
| `revocation.sync` | bidirectional / anti-entropy | แลกเปลี่ยน Revocation Tombstones ที่ขาดหายหลัง Handshake | FR-11 |
| `ping` / `pong` | bidirectional | heartbeat | FR-10 |
| `error` | bidirectional | แจ้งข้อผิดพลาด | — |

### 7.3 กฎทั่วไป

- ข้อความทุกประเภทยกเว้น `error` MUST มาจาก peer ที่ผ่าน `hello` แล้ว
- ผู้รับ MUST dedup ด้วย `msg_id` (LRU `SEEN_MSG_CACHE` = 200 entries ต่อเครื่อง)
- ผู้รับ MUST merge Hybrid Logical Clock (HLC) ทุกครั้งที่ได้รับข้อความ (ทุก type) ตาม §10.1

### 7.4 Payload Schemas

#### 7.4.1 `hello` / `hello.ack`

```json
{
  "device_id": "550e8400-e29b-41d4-a716-446655440000",
  "name": "MacBook Pro ของเจ",
  "os": "macos",
  "tier": 1,
  "v": 1,
  "min_v": 1,
  "app_version": "1.0.0",
  "capabilities": ["clip.text", "clip.image", "clip.push", "file", "file.resume"],
  "tombstones_hash": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  "tombstone_count": 0,
  "clip_head": { "hlc": { "l": 1757280000000, "c": 0, "d": "..." }, "origin": "550e8400-...", "hash": "9f86d0...", "msg_id": "6f1c2c1e-..." }
}
```

| Field | Type | คำอธิบาย |
|---|---|---|
| `v` | int | Wire protocol version ปัจจุบันของผู้ส่ง (เช่น 1) |
| `min_v` | int | Wire protocol version ต่ำสุดที่ยังรองรับได้ (เช่น 1) |
| `tombstones_hash` | hex | SHA-256 ของรายการ Revocation Tombstones ทั้งหมดในเครื่อง (สำหรับ Anti-Entropy) |
| `tombstone_count` | int | จำนวน Revocation Tombstones ที่บันทึกไว้ |
| `capabilities` | string[] | ดูตาราง capabilities ด้านล่าง |
| `clip_head` | object? | รายการล่าสุดที่ยอมรับ (null ถ้าไม่มี) — ใช้ใน Catch-up §10.7 |

| Capability | ความหมาย |
|---|---|
| `clip.text` | รับ/ส่ง `text/plain`, `text/uri-list` |
| `clip.image` | รับ/ส่ง `image/png`, `image/jpeg` |
| `clip.push` | เขียน clipboard ได้ทันทีเมื่อได้รับ (Tier 1, Tier 2) — Tier 3 MUST NOT ประกาศ |
| `file` | รับไฟล์ได้ |
| `file.resume` | รองรับ resume (§12.4) |

- `device_id` MUST ตรงกับ CN ของ client/server cert และ record ใน Trusted Store มิฉะนั้น → `E_NOT_PAIRED`

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
| `size` | int | ขนาด raw content (bytes), MUST $\le$ `CLIPBOARD_MAX_SIZE` (32 MiB) |
| `is_concealed` | bool | MUST เป็น `false` เสมอใน v1 (ดูกฎข้อ 3) |
| `ttl_seconds` | int? | null = ไม่หมดอายุ; ถ้ามีค่า MUST อยู่ในช่วง 5–3600 |
| `inline` | string? | Base64 ของ raw content (ใช้เฉพาะข้อความ text ขนาด $\le$ 32 KiB) |
| `blob_id` | uuid? | อ้างอิง blob บน Data Plane (§9.3) สำหรับข้อมูลขนาด $> 32$ KiB หรือรูปภาพทุกขนาด |
| `meta` | object | `width`/`height` เป็น pixel, `dpi` เป็นตัวเลข (เช่น 72, 144) — ใช้กับรูปเท่านั้น |

> **ความชัดเจนของขีดจำกัดขนาดข้อมูล (Payload Boundary Specification):**  
> 1. **Control Plane WS Frame Max (`WS_MAX_MESSAGE_SIZE`):** `64 KiB` (ปฏิเสธด้วย `E_PAYLOAD_TOO_LARGE` หากเฟรมเกินนี้)  
> 2. **Clipboard Inline Text Max (`CLIPBOARD_INLINE_THRESHOLD`):** `32 KiB` (หากข้อความ text $\le 32$ KiB จะส่งแบบ `inline` ใน Control Plane)  
> 3. **Clipboard Blob Routing Threshold:** `> 32 KiB` (หาก text $> 32$ KiB หรือเป็นรูปภาพทุกขนาด จะส่งเป็น `blob_id` ผ่าน Data Plane HTTP)  
> 4. **Clipboard Max Content Size (`CLIPBOARD_MAX_SIZE`):** `32 MiB` (33,554,432 bytes — ขนาดรวมสูงสุดของภาพ/ข้อความคลิปบอร์ด หากเกินจะถูกปฏิเสธด้วย `E_PAYLOAD_TOO_LARGE`)

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

ส่งตรงไปยังโหนดที่ถูกเพิกถอน (Direct Unicast):
```json
{
  "device_id": "550e8400-e29b-41d4-a716-446655440000",
  "target_device_id": "b2c3d4e5-6a7b-8c9d-0e1f-2a3b4c5d6e7f",
  "reason": "user_revoked"
}
```

#### 7.4.10 `cluster.revocation` (Signed Cluster-Wide Broadcast)

กระจายคำสั่งเพิกถอนไปยังทุกโหนดที่เชื่อถือในคลัสเตอร์ (Gossip Flooding):
```json
{
  "revocation_token": {
    "revoker_id": "550e8400-e29b-41d4-a716-446655440000",
    "revoked_id": "b2c3d4e5-6a7b-8c9d-0e1f-2a3b4c5d6e7f",
    "revoked_fp": "5e884898da28047151d0e56f8dc6292773603d0d6aabbdd62a11ef721d1542d8",
    "timestamp": 1757280000000,
    "signature": "MEUCIQC...<base64 ECDSA P-256 signature>..."
  }
}
```
- `signature` สร้างจาก Private Key ของ `revoker_id` เซ็นครอบคลุมสตริง:
  `UTF8("dropclip-revoke-v1:" ‖ revoker_id ‖ ":" ‖ revoked_id ‖ ":" ‖ revoked_fp ‖ ":" ‖ timestamp)`
- โหนดผู้รับ MUST ตรวจสอบว่า `revoker_id` เป็นโหนดที่ตนเชื่อถือ (อยู่ใน Trusted Store) และ verify ลายเซ็นผ่านก่อน จึงยอมรับและเพิกถอน `revoked_fp`

#### 7.4.11 `ping` / `pong`

```json
{ "seq": 42 }
```
`pong.seq` MUST เท่ากับ `ping.seq` ที่ตอบ

#### 7.4.12 `error`

```json
{ "code": "E_UNSUPPORTED_VERSION", "message": "no mutually supported protocol version", "fatal": true, "ref_msg_id": null }
```
`message` MUST NOT มีเนื้อหา clipboard, path เต็ม หรือข้อมูลลับ

---

## 8. Error Code Registry

| Code | HTTP | Fatal | ความหมาย |
|---|---|---|---|
| `E_UNSUPPORTED_VERSION` | 400 | ✅ | ไม่มีช่วงโปรโตคอลเวอร์ชันที่รองรับร่วมกัน (Version Negotiation ล้มเหลว) |
| `E_NOT_PAIRED` | 403 | ✅ | fingerprint ไม่อยู่ใน Trusted Store (รวมถึงหลังถูก revoke — FR-11) |
| `E_REVOKED` | 403 | ✅ | ใช้เป็น reason ประกอบ `device.revoked` เท่านั้น |
| `E_MALFORMED` | 400 | ⬜ | JSON parse ไม่ได้ / field ขาด / type ผิด / magic bytes ผิด |
| `E_PAYLOAD_TOO_LARGE` | 413 | ⬜ | ข้อความ WS เกิน 64 KiB หรือ clipboard เกิน `CLIPBOARD_MAX_SIZE` (32 MiB) |
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
| `POST` | `/api/v1/pair` | TLS (ไม่มี client cert) + RateLimit | เริ่มจับคู่และส่ง Commitment B (`commitment_B`) | FR-02 |
| `POST` | `/api/v1/pair/confirm` | TLS (ไม่มี client cert) + RateLimit | เปิดเผย `nonce_B` เพื่อให้ Host ตรวจสอบ Commitment | FR-02 |
| `POST` | `/api/v1/pair/finalize` | TLS (ไม่มี client cert) + RateLimit | ยืนยันผลการเปรียบเทียบ SAS จากผู้ใช้ (`match`/`mismatch`) | FR-02 |
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

### 9.2 `POST /api/v1/pair`, `/api/v1/pair/confirm` และ `/api/v1/pair/finalize`

**Request — `POST /api/v1/pair` (Step 5)**
```json
{
  "v": 1,
  "min_v": 1,
  "device_id": "b2c3d4e5-6a7b-8c9d-0e1f-2a3b4c5d6e7f",
  "name": "Windows PC ที่ทำงาน",
  "os": "windows",
  "tier": 1,
  "fp": "5e884898da28047151d0e56f8dc6292773603d0d6aabbdd62a11ef721d1542d8",
  "commitment_B": "c75a3af628ada8bd606909cf780ee15cec594a2e7c4b4d379bc54ceb1b955bc1",
  "method": "qr"
}
```
*(ห้ามส่ง PIN, ค่าแฮชของ PIN หรือ nonce_B ในขั้นตอนนี้เด็ดขาด เพื่อป้องกันการโจมตี Offline MITM)*

**Response 200 — `/pair` (Step 7)**
```json
{
  "pair_id": "0b7e21a8-8e6d-4c3a-9f5b-1c2d3e4f5a6b",
  "device_id": "550e8400-e29b-41d4-a716-446655440000",
  "name": "MacBook Pro ของเจ",
  "os": "macos",
  "tier": 1,
  "fp": "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08",
  "nonce_A": "MDEyMzQ1Njc4OWFiY2RlZg=="
}
```

**Request — `POST /api/v1/pair/confirm` (Step 10)**
```json
{
  "pair_id": "0b7e21a8-8e6d-4c3a-9f5b-1c2d3e4f5a6b",
  "nonce_B": "ZmVkY2JhOTg3NjU0MzIxMA=="
}
```

**Response 200 — `/pair/confirm`**
```json
{
  "pair_id": "0b7e21a8-8e6d-4c3a-9f5b-1c2d3e4f5a6b",
  "status": "commitment_verified"
}
```
*(ถ้า Commitment ไม่ตรง ตอบกลับ `401 E_PAIRING_INVALID`)*

**Request — `POST /api/v1/pair/finalize` (Step 13)**
```json
{
  "pair_id": "0b7e21a8-8e6d-4c3a-9f5b-1c2d3e4f5a6b",
  "result": "match"
}
```

**Response — `/pair/finalize` (Step 14)**
`200 {"result": "paired"}` | `401 E_SAS_FAILED` | `410 E_NONCE_EXPIRED` (เกิน `PAIR_CONFIRM_TIMEOUT` = 120 s) | `429`

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
X-DropClip-HLC: 1757280000000:0:6f1c2c1e-6a43-4c4e-9d0c-0b6f3a5b1e27
X-DropClip-Ts: 1757280000000
X-DropClip-TTL: 60                      (optional)
X-Content-SHA256: a591a6d4...

Hello World
```

- Body คือ raw content (ไม่ base64) — ผู้ส่ง SHOULD stream จากไฟล์เพื่อคุม memory (NFR-R03B)
- `Content-Length` MUST ≤ `CLIPBOARD_MAX_SIZE`
- ผู้รับ MUST ประมวลผลเหมือน `clipboard.update` ขาเข้าทุกประการ (§10.3) รวมถึง dedup, Clock Drift check และ HLC LWW
- **Response 200:** `{ "applied": true, "hlc": { "l": 1757280000001, "c": 0, "d": "<receiver_id>" } }` — ผู้ส่ง MUST merge `hlc`
- ผู้รับที่เป็น Tier 1 SHOULD broadcast ต่อไปยัง peer อื่นของตัวเอง? **ไม่ — v1 ไม่มี relay** ผู้ส่ง (มือถือ) MUST ส่งตรงไปยังทุก desktop ที่เลือก/ออนไลน์

### 9.5 `GET /api/v1/clipboard/latest`

- `200` + headers ชุดเดียวกับ §9.4 (รวมถึง `X-DropClip-HLC: <l>:<c>:<d>`) + raw body ของ `clip_head` ปัจจุบัน
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
| `_hlc` | Hlc | ✅ (`state.json`) | Hybrid Logical Clock `{ "l": int64, "c": int, "d": string }` — MUST persist ทุกครั้งที่ tick จาก local event; merge จาก remote persist แบบ debounce ≤ 1 s |
| `_head` | ClipEntry? | ⬜ | รายการล่าสุดที่ยอมรับ `{hlc, origin, hash, msg_id, content_type, ttl, data}` |
| `_lastAppliedHash` | hex? | ⬜ | hash ของข้อมูลที่ DropClip เพิ่งเขียนลง OS clipboard |
| `_suppressUntil` | DateTime | ⬜ | หมดเวลา suppression window |
| `_seenMsgIds` | LRU(200) | ⬜ | dedup |
| `_history` | Ring(20) | ⬜ | Catch-up queue (E-04) |

> **ทำไมต้องใช้ HLC แทน Pure Lamport (ADR-008):** ถือเครื่องออฟไลน์ไปนานหลายชั่วโมง แล้วผู้ใช้คัดลอกข้อมูลใหม่บนเครื่องนั้น หากใช้ Pure Lamport ค่า clock จะยังต่ำกว่าอุปกรณ์อื่นที่ซิงก์กันอยู่ เมื่อเชื่อมต่อกลับมา ข้อมูลใหม่จะถูก LWW ทิ้งเงียบ ๆ เพราะแพ้ clock เก่า! แต่ HLC ผสานเวลาจริงของเครื่อง (`l`) ทำให้การคัดลอกใหม่บนเครื่องออฟไลน์มีค่า `l` สูงกว่าเสมอ และชนะ LWW ตามที่ผู้ใช้คาดหวังอย่างถูกต้อง ขณะที่ตัวนับ `c` ยังทำหน้าที่แก้ปัญหาหากเกิดเหตุการณ์ภายในมิลลิวินาทีเดียวกัน

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

  // Step 4: Advance HLC แล้ว broadcast ไปทุก peer ที่ CONNECTED (offline → Outbound Queue)
  _hlc = _hlc.tick(now().millisecondsSinceEpoch);
  persistHlc();

  final env = Envelope(
    type: 'clipboard.update',
    origin: myId,
    hlc: _hlc,
    ts: now().millisecondsSinceEpoch,
    payload: ClipboardPayload(
      contentType: e.contentType,
      hash: hash,
      size: raw.length,
      isConcealed: false,
      ttlSeconds: config.clipboardTtlSeconds,
      inline: useBlob ? null : base64(raw),
      blobId: blobId,
      meta: e.imageMeta,
    ),
  );
  _accept(env, raw);                               // ตั้ง _head + _history
  if (env.payload.ttlSeconds != null) _scheduleClear(hash, env.payload.ttlSeconds!);
  broadcast(env, onlyTo: peers.where((p) => p.supports(e.contentType)));
}
```

### 10.3 Inbound — เมื่อได้รับ `clipboard.update` หรือ `POST /api/v1/clipboard` (FR-04 ขารับ)

```dart
Future<void> onRemoteClipboardUpdate(Envelope env, Peer sender) async {
  final nowMs = now().millisecondsSinceEpoch;

  // Step 1: ป้องกัน Clock Drift ผิดปกติเกินขอบเขตยอมรับ (MAX_CLOCK_DRIFT = 60 วินาที)
  if (env.hlc.l - nowMs > MAX_CLOCK_DRIFT_MS) {
    log.warn('clipboard.clock_drift_exceeded', {'remote_l': env.hlc.l, 'local_ms': nowMs});
    return; // ป้องกัน remote node ที่ตั้งนาฬิกาอนาคตเข้ายึด LWW
  }

  // Step 2: HLC merge — MUST ทำก่อนอย่างอื่นเสมอ
  _hlc = _hlc.merge(env.hlc, nowMs);

  // Step 3: ทิ้งข้อมูลที่ตัวเองสร้าง (กัน loop)
  if (env.origin == myId) return;

  // Step 4: Dedup ด้วย msg_id (กันส่งซ้ำจาก reconnect / outbound queue)
  if (!_seenMsgIds.addIfAbsent(env.msgId)) return;

  // Step 5: Policy — ปิดซิงก์ / type ไม่อนุญาต / concealed → ทิ้ง
  if (!config.clipboardSyncEnabled || !config.allows(env.payload.contentType)) return;
  if (env.payload.isConcealed) return;

  // Step 6: Last-Writer-Wins ด้วยการเปรียบเทียบ HLC (l, c, d)
  if (_head != null) {
    if (env.hlc.compareTo(_head.hlc) < 0) {
      log.debug('clipboard.dropped_stale_hlc');
      return; // ข้อมูลนี้เก่ากว่า _head ปัจจุบัน
    }
  }

  // Step 7: ได้ raw bytes
  final raw = env.payload.blobId != null
      ? await fetchBlob(sender, env.payload.blobId!)        // GET /api/v1/blob/{id}
      : base64Decode(env.payload.inline!);

  // Step 8: Integrity + validation (magic bytes ของรูป — §11.3)
  if (sha256(raw) != env.payload.hash) return sendError(sender, 'E_CHECKSUM_MISMATCH', env);
  if (!FormatNormalizer.validate(raw, env.payload.contentType)) return sendError(sender, 'E_MALFORMED', env);

  _accept(env, raw);

  // Step 9: Tier 3 (iOS) — เก็บไว้รอ foreground/Widget เท่านั้น (§10.6)
  if (!myCapabilities.contains('clip.push')) return;

  // Step 10: ตั้ง suppression ก่อนเขียน — ลำดับสำคัญมาก
  _lastAppliedHash = env.payload.hash;
  _suppressUntil = now().add(SUPPRESSION_WINDOW);           // 800 ms

  // Step 11: แปลงเป็นรูปแบบ native แล้วเขียนลง OS clipboard (retry ตาม §14.1)
  await clipboard.write(FormatNormalizer.toNative(raw, env.payload.contentType, myOs));

  // Step 12: TTL
  if (env.payload.ttlSeconds != null) _scheduleClear(env.payload.hash, env.payload.ttlSeconds!);
}
```

### 10.4 Sensitive Content Filter (FR-05, NFR-S04)

ระบบต้องทำการกรองข้อมูลที่ถูกตั้งค่าเป็นข้อมูลลับอย่างเข้มงวด โดยระบุ Marker ชัดเจนระดับ OS:

| OS | สัญญาณ concealed / Sensitive Markers | การกระทำของ Native layer |
|---|---|---|
| macOS | Pasteboard type `org.nspasteboard.ConcealedType`, `org.nspasteboard.TransientType`, `com.agilebits.onepassword`, `org.nspasteboard.AutoGeneratedType` (ไม่ใช่ข้อมูลลับ แต่ข้ามเพื่อไม่ซิงก์ข้อมูลที่แอปสร้างอัตโนมัติ) | ส่ง event `is_concealed: true` **โดยไม่อ่านเนื้อหา** |
| Windows | Registered format `ExcludeClipboardContentFromMonitorProcessing`, `CanIncludeInClipboardHistory` = 0, `CanUploadToCloudClipboard` = 0 | ส่ง event `is_concealed: true` **โดยไม่อ่านเนื้อหา** |
| Android | `ClipDescription.EXTRA_IS_SENSITIVE` (`android.content.extra.IS_SENSITIVE` = true) | ยกเลิกการอ่าน/ส่งออกทันที |
| iOS | Sandboxed — เข้าถึงได้เฉพาะเมื่อผู้ใช้เลือกกดส่งผ่าน Share Extension โดยเจตนา | กรองตาม user intent |

- Log ได้เฉพาะ `{type, size}` — MUST NOT log เนื้อหาหรือคำนวณ hash ของข้อมูล concealed
- ระบบ MUST กรองข้อมูลที่มี **Known OS Sensitive Marker ดังกล่าวได้ 100%** (NFR-S04) จากการทดสอบคัดลอกจาก Password Managers (1Password, Bitwarden, KeePassXC, Apple Keychain) และโหมด Private Browsing

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
- หลัง `hello`/`hello.ack` แต่ละฝ่ายเทียบ `clip_head` ของตัวเองกับของอีกฝ่ายตามกฎ LWW (§10.3 step 6)
- ฝ่ายที่ head ใหม่กว่า MUST ส่ง **envelope เดิมของ head 1 รายการ** (`msg_id`, `origin`, `hlc` เดิม) — ไม่ส่งทั้ง 20
- รายการที่ TTL หมดแล้ว MUST NOT ถูกส่ง
- **Partition semantics:** event ที่เกิดระหว่าง network partition ถือเป็น concurrent — ทุกเครื่อง converge ไปค่าเดียวกันตาม `(hlc, origin)` แต่ไม่รับประกันว่าเป็นค่าที่ "ล่าสุดตามนาฬิกาจริง"

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

### 12.4 Resume Rules & 64 MiB Checkpoints (FR-09)

1. เมื่อเชื่อมต่อกลับมา ผู้ส่ง MUST เรียก `GET /api/v1/file/{t}/{i}/status` ของ item ที่ยังไม่ `complete`
2. **Sidecar Checkpointing:** ผู้รับบันทึก Checkpoint ลงใน sidecar `<item_id>.part.json` ทุก ๆ `CHECKPOINT_INTERVAL` = 64 MiB (67,108,864 bytes) ประกอบด้วย `{ offset, sha256_prefix }`
3. ผู้รับ truncate `.part` ลงขอบ chunk (1 MiB) แล้ว streaming rehash `.part` ตั้งแต่ byte 0 ด้วย SHA-256 ตัวใหม่ (MUST NOT พยายามกู้คืน hasher state — `package:crypto` ไม่ export state และห้ามเขียน crypto เอง) ระหว่างทาง MUST เทียบ digest ณ ทุก checkpoint กับ `sha256_prefix` ใน sidecar หากไม่ตรงให้ตัด `offset` ลงไปที่ checkpoint สุดท้ายที่ตรง (ไม่มีเลย → `0`) แล้วตอบ `offset` + `last_chunk_sha256` — เวลา resume จึงแปรผันตามขนาด `.part` (ไม่มีเป้า < 200 ms)
4. ผู้ส่งคำนวณ SHA-256 ของ chunk เดียวกันจากไฟล์ต้นทาง → ตรง: `POST` ด้วย `X-Offset: offset`; ไม่ตรง: `POST` ด้วย `X-Offset: 0` (เริ่ม item ใหม่)
5. ตรวจ SHA-256 ทั้งไฟล์เป็นขั้นตอนสุดท้ายเสมอ
6. `.part` ที่ค้างเกิน `PARTIAL_RETENTION` (24 ชม.) MUST ถูกลบตอนเปิดแอป

---

## 13. Device Management & Signed Cluster Revocation (FR-11, SF-08)

เมื่อผู้ใช้สั่งเพิกถอนอุปกรณ์ (เช่น โน้ตบุ๊กสูญหาย หรือปลดระวางเครื่อง) ระบบ MUST ดำเนินการดังนี้:

### 13.1 Local Revocation Enforcement (ภายในเครื่องที่สั่ง)
ลำดับ MUST เป็นดังนี้ และทั้งหมด MUST เสร็จสิ้นภายใน **1 วินาที** (NFR-S05):
1. ลบ fingerprint (`revoked_fp`) ออกจาก Trusted Device Store **ก่อน** ทันที (connection ใหม่จากเครื่องนั้นจะถูกปฏิเสธด้วย `403 E_NOT_PAIRED`)
2. ส่งข้อความ `device.revoked` ผ่าน WebSocket ไปยังเครื่องที่ถูกเพิกถอนแบบ Best-effort (timeout 200 ms)
3. ปิดทุก WebSocket connection และ HTTP stream ที่ผูกกับอุปกรณ์นั้นทันที (close code `4004`) และยกเลิก transfer ที่ค้างอยู่
4. ล้าง peer ออกจาก Outbound Queue และ Catch-up target

### 13.2 Cluster-Wide Signed Revocation Broadcast (ทั่วทั้งกลุ่มอุปกรณ์)
เพื่อแก้ปัญหา Revocation มีผลเฉพาะเครื่องเดี่ยว โดยเครื่องอื่นในวง (เช่น Desktop เครื่องอื่น หรือ Android) ยังคงเชื่อมต่อกับเครื่องที่หายอยู่:
1. เครื่องที่สั่ง Revoke สร้าง **`RevocationBroadcastToken`**:
   ```json
   {
     "revoker_id": "<my_device_id>",
     "revoked_id": "<target_device_id>",
     "revoked_fp": "<target_device_fingerprint>",
     "timestamp": 1757280000000,
     "signature": "<ECDSA P-256 signature>"
   }
   ```
2. ทำการ Sign ด้วย ECDSA P-256 Private Key ของตนเอง ครอบคลุมสตริง:
   `UTF8("dropclip-revoke-v1:" ‖ revoker_id ‖ ":" ‖ revoked_id ‖ ":" ‖ revoked_fp ‖ ":" ‖ timestamp)`
3. Broadcast ข้อความ `cluster.revocation` (§7.4.10) ไปยัง **ทุก Peer ที่กำลังเชื่อมต่ออยู่ (Connected Peers)** ในวง LAN
4. **โหนดในคลัสเตอร์ที่ได้รับข้อความ:**
   - ตรวจสอบว่า `revoker_id` เป็นโหนดที่ตนเชื่อถือใน Trusted Store (หากไม่เชื่อถือ → drop)
   - ตรวจสอบความสดของเวลา `timestamp` (ห้ามเกิน 24 ชม. จากเวลาปัจจุบัน)
   - ตรวจสอบลายเซ็น ECDSA ด้วย Public Key / Cert ของ `revoker_id` ที่ Pin ไว้ในเครื่อง
    - หากลายเซ็นถูกต้อง: **(ก) Quarantine ทันที** — ตัดการเชื่อมต่อและปิด Socket กับอุปกรณ์นั้นใน < 1 วินาที, ปฏิเสธ connection ใหม่จาก `revoked_fp` ด้วย `403 E_NOT_PAIRED`, บันทึก token ลง `revoked_tombstones.json` สถานะ `pending` และส่งต่อ (Gossip Forward — ข้อยกเว้นของ §2.3) ไปยัง Peer อื่น (พร้อม LRU Cache ป้องกันการส่งซ้ำ); **(ข) ผู้ใช้ของเครื่องนี้ยืนยัน** — "ยืนยันเพิกถอน" → ลบ `revoked_fp` ออกจาก Trusted Store ถาวรและเปลี่ยน tombstone เป็น `confirmed`; "ปฏิเสธ" → คืนสถานะ trusted ให้ `revoked_id` และนำ `revoker_id` เข้าสู่ quarantine แทน (ผู้สั่งน่าจะเป็นเครื่องที่ถูกขโมย)
    - Token ที่ `revoker_id` อยู่ในสถานะ quarantine หรือถูกเพิกถอนแล้ว MUST ถูก drop; ถ้าได้รับ token ที่สองเครื่องสั่ง revoke กันเอง MUST quarantine ทั้งคู่และรอผู้ใช้ตัดสิน
5. **การป้องกันเครื่องที่ถูกขโมยสั่ง Revoke เครื่องอื่น (No Self-Revocation by Proxy & Quarantine-then-Confirm):**
   - **No Self-Revocation by Proxy:** โหนดที่ได้รับ `cluster.revocation` หากพบว่า `revoked_id == my_device_id` **MUST NOT** เพิกถอนตนเองหรือลบ Trusted Store ของตนเองเด็ดขาด ป้องกันกรณีเครื่องที่ถูกขโมยชิงส่งคำสั่งมาปิดสิทธิ์เครื่องจริง
   - **Interactive User Notification:** เมื่อโหนดได้รับคำสั่งเพิกถอนเครื่องอื่นในคลัสเตอร์ แอป MUST แสดง System Notification หรือ In-App Banner แจ้งเตือนผู้ใช้ทันที: *"อุปกรณ์ [Device Name] ถูกสั่งเพิกถอนออกจากกลุ่มโดย [Revoker Name]"* พร้อมปุ่ม "ยืนยันเพิกถอน" / "ปฏิเสธ" ตามข้อ 4(ข) — เครื่องที่ถูกขโมยจึงทำได้อย่างมากแค่ตัดการเชื่อมต่อชั่วคราว (DoS) จนผู้ใช้กดปฏิเสธ แต่ลบ trust ของเครื่องจริงถาวรไม่ได้
6. **Persistent Revocation Tombstones & Handshake Anti-Entropy (สำหรับเครื่องที่ออฟไลน์):**
   - ทุกเครื่องบันทึกประวัติการเพิกถอนลงในไฟล์ถาวร `revoked_tombstones.json` (`RevocationBroadcastToken[]`)
   - ในขั้นตอน Handshake `hello` / `hello.ack` (§7.4.1) ทั้งสองฝ่ายส่ง `tombstones_hash` และ `tombstone_count` หากตรวจพบว่าค่า hash ไม่ตรงกัน หรือจำนวนไม่เท่ากัน โหนดที่มีรายการใหม่กว่าจะส่งข้อความ `revocation.sync` พร้อม Signed Token ที่ขาดหายไปให้อีกฝ่ายทันที
   - กลไก Anti-Entropy นี้รับประกันว่าเครื่องที่ออฟไลน์ไป เมื่อกลับมาเชื่อมต่อกับโหนดใด ๆ ในคลัสเตอร์ จะได้รับประวัติการเพิกถอนครบถ้วน 100% ป้องกันเครื่องที่ถูก Revoke ลักลอบเชื่อมต่อกับเครื่องที่เพิ่งออนไลน์
7. **เกณฑ์การยอมรับ (Acceptance Criteria):**
   - เครื่องที่สั่งเพิกถอน: ยุติการเชื่อมต่อและเพิกถอนในเครื่องตนเองเสร็จสิ้นภายใน **< 1.0 วินาที** (NFR-S05)
   - คลัสเตอร์ในวง LAN: โหนดที่ออนไลน์ทั้งหมดได้รับสัญญาณ Revocation และตัดการเชื่อมต่อกับเครื่องที่ถูกเพิกถอนเสร็จสิ้นภายใน **< 2.0 วินาที**

ฝั่งที่ได้รับ `device.revoked` ตรง:
- SHOULD ลบผู้เพิกถอนออกจาก Trusted Store ของตัวเอง และแจ้งผู้ใช้ผ่าน System Notification
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

#### 14.2 Android (Tier 2)

| Channel / Service | Method / Event | คำอธิบาย & OS Constraints |
|---|---|---|
| `dropclip/android/service` | `startService`, `stopService`, `isRunning` | Foreground Service (`START_STICKY`, **`foregroundServiceType="connectedDevice"`** ตาม ADR-007 — ห้ามใช้ `dataSync` เพราะ Android 15 จำกัดเวลาทำงานรวม ~6 ชม./วัน) |
| `dropclip/android/service` | `requestBatteryExemption` | ขอยกเว้น battery optimization เพื่อป้องกัน Doze mode ตัด WebSocket |
| `dropclip/discovery` | `acquireMulticastLock`, `releaseMulticastLock` | ถือ **`WifiManager.MulticastLock`** ระหว่างการค้นหา mDNS ป้องกัน OS ดักทิ้งแพ็กเก็ต UDP 5353 |
| `dropclip/clipboard` | `write`, `clear`, `changeToken` | ใช้ร่วมกับ §14.1 (เขียนได้โดยตรงจาก Foreground Service) |
| `dropclip/android/events` | `{"action": "send_clipboard", "snapshot": ClipSnapshot}` | มาจาก QS Tile / Notification Action ผ่าน Transient Activity (Android 14+ MUST ใช้ **`PendingIntent`** สำหรับ `startActivityAndCollapse` ป้องกัน SecurityException) |
| `dropclip/android/events` | `{"action": "share", "uris": [...], "text": ...}` | มาจาก Share Sheet (`ACTION_SEND`, `ACTION_SEND_MULTIPLE`) |
| `dropclip/media` | `saveToMediaStore({path, mime})` | SW-03 |

### 14.3 iOS (Tier 3)

| Component | สัญญา & OS Constraints |
|---|---|
| App Group | `group.com.dropclip.shared` — เก็บ `identity.json`, `trusted_devices.json.enc`, `state.json`, และ cached active peers ร่วมกับ Share Extension |
| Keychain Access Group | `$(TeamID).com.dropclip.shared` — private key (`dropclip.identity.p256`) + store key |
| Share Extension | Native Swift (ไม่ใช้ Flutter engine เพื่อคุม RAM < 30 MB — NFR-R03B) ใช้ **`URLSessionConfiguration.background(withIdentifier:)`** ร่วมกับ X.509 client cert identity จาก Keychain เพื่อสตรีมไฟล์ขนาดใหญ่ (สูงสุด 4 GB) ได้โดยไม่ถูก Jetsam kill |
| Discovery | ใช้ **`NWBrowser`** ผ่าน Platform Channel และระบุ **`NSBonjourServices`** (`_dropclip._tcp`) ใน `Info.plist` (หลีกเลี่ยงการใช้ raw multicast UDP socket ซึ่งต้องขอ entitlement พิเศษจาก Apple) |
| `dropclip/ios` channel | `pasteboardWrite`, `pasteboardRead` (เรียกได้เฉพาะ foreground — มีผลกระทบจาก **iOS 16+ "Allow Paste" System Prompt** ซึ่งถูกนับรวมในตัวชี้วัดการโต้ตอบ 1–2 ขั้นตอน), `savePhoto({path})` (PhotoKit add-only) |
| AppIntents & Widgets | `SendClipboardIntent`, `PullClipboardIntent` — สำหรับ iOS 17+ รองรับ Interactive Widgets และ iPhone 15 Pro+ Action Button; **Fallback สำหรับ iOS 15/16:** ใช้วิธีแตะ Widget เพื่อ Launch เข้าแอป หรือรันคำสั่งลัดผ่าน Apple Shortcuts Automation |

### 14.4 Secure Storage (ทุกแพลตฟอร์ม)

Dart interface ที่ทุกแพลตฟอร์ม MUST implement (`dropclip_core`):
```dart
abstract interface class SecureKeyStore {
  Future<Uint8List?> read(String key);
  Future<void> write(String key, Uint8List value);
  Future<void> delete(String key);
}
// Keys: 'dropclip.identity.p256'     (ECDSA P-256 private key)
//       'dropclip.store.key'         (AES-256-GCM key สำหรับ trusted_devices.json.enc)
```

### 14.5 Auto-Start (FR-12)

| OS | กลไก | Launch arg |
|---|---|---|
| macOS | `SMAppService.mainApp.register()` (macOS 13+); macOS 12 ใช้ LaunchAgent plist ใน `~/Library/LaunchAgents` | `--hidden` |
| Windows | `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` → `"<exe>" --hidden` | `--hidden` |

เมื่อเปิดด้วย `--hidden` แอป MUST อยู่ใน Tray/Menubar เท่านั้น ห้ามเปิดหน้าต่างหรือ pop-up (NFR-U03)
*(หมายเหตุ: บน Windows 10/11 ระบบมี mDNS responder ประจำ OS บนพอร์ต 5353 อยู่แล้ว จึง SHOULD ใช้ DNS-SD API ของระบบตาม §3.1 แทนการเปิด socket เอง และจัดการหน้าต่าง Windows Firewall Prompt ตอน Onboarding)*

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
| E-04 `ClipEntry` | `msg_id, content_type, hash, size, is_concealed, ttl_seconds, data, hlc, origin, received_at` |

### 15.5 `<item_id>.part.json` (E-05 — Resumable Checkpoint Sidecar)
```json
{
  "version": 2,
  "transfer_id": "c3d4e5f6-...",
  "item_id": "i1",
  "path": "Photos/vacation.jpg",
  "size": 2458123,
  "sha256": "d2a84f...",
  "offset": 2097152,
  "state": "in_progress",
  "peer_id": "b2c3d4e5-...",
  "checkpoints": [
    { "offset": 67108864, "sha256_prefix": "e3b0c442..." },
    { "offset": 134217728, "sha256_prefix": "a1b2c3d4..." }
  ],
  "updated_at": 1757280000000
}
```

### 15.6 `config.json` (E-06, FR-12)
```json
{
  "version": 1,
  "device_name": "MacBook Pro ของเจ",
  "auto_accept": false,
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

### 15.7 `state.json` (HLC Persistence)
```json
{
  "version": 2,
  "hlc": {
    "l": 1757280000000,
    "c": 0,
    "d": "550e8400-e29b-41d4-a716-446655440000"
  }
}
```

---

## 16. Limits & Constants

| Constant | Value | เหตุผล / SRS |
|---|---|---|
| `PROTOCOL_VERSION` | 1 | — |
| `MIN_SUPPORTED_VERSION` | 1 | §2.4 (Version Negotiation) |
| `MAX_CLOCK_DRIFT` | 60 s (60,000 ms) | §10.3, T-D03 (ป้องกัน future clock drift ยึดสิทธิ์ LWW) |
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
| **อุปกรณ์ที่สูญหาย** | มี private key ที่ถูกต้อง | Revocation ภายใน 1 วินาที + quarantine-then-confirm กันการ revoke เครื่องจริง (§13) |
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
  if (RegExp(r'[\u202A-\u202E\u2066-\u2069]').hasMatch(input)) throw InvalidPathException('bidi'); // V13
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
    if (RegExp(r'^(CON|PRN|AUX|NUL|CONIN\$|CONOUT\$|COM[0-9¹²³]|LPT[0-9¹²³])$').hasMatch(stem)) {
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

### 18.1 SAS — QR mode (Dual Nonce Conformance §5.5.1)

```
fp_A     = "0000000000000000000000000000000000000000000000000000000000000000"
fp_B     = "1111111111111111111111111111111111111111111111111111111111111111"
nonce_A  = base64 "MDEyMzQ1Njc4OWFiY2RlZg=="   (= ASCII "0123456789abcdef", 16 bytes)
nonce_B  = base64 "ZmVkY2JhOTg3NjU0MzIxMA=="   (= ASCII "fedcba9876543210", 16 bytes)

sas_input  = UTF8(fp_A) ‖ UTF8(fp_B) ‖ nonce_A ‖ nonce_B   (160 bytes; fp_A < fp_B)
sas_hash   = f7ea7239a0b48b63c1f80bf2d1f81fc56c486b0f1a558b258a986ce12d39d14c
uint32_be  = 0xf7ea7239 = 4159337017
sas        = 4159337017 mod 1000000 = "337017"
```
และ MUST ได้ `"337017"` เมื่อสลับ `fp_A` ↔ `fp_B` (symmetry)

*(หมายเหตุ: กรณี single-nonce legacy `calculateSas(fp_A, fp_B, nonce_A)` ขนาด 144 bytes ให้ผลลัพธ์คือ `"579318"` เพื่อการทดสอบความเข้ากันได้ย้อนหลัง)*

### 18.2 SAS — PIN mode (OOB Salted)

```
fp_A     = "0000000000000000000000000000000000000000000000000000000000000000"
fp_B     = "1111111111111111111111111111111111111111111111111111111111111111"
nonce_A  = base64 "MDEyMzQ1Njc4OWFiY2RlZg=="   (= ASCII "0123456789abcdef", 16 bytes)
nonce_B  = base64 "ZmVkY2JhOTg3NjU0MzIxMA=="   (= ASCII "fedcba9876543210", 16 bytes)
pin      = "123456"
pin_salt = UTF8("dropclip-pin-salt-v1:123456")

sas_input = UTF8(fp_A) ‖ UTF8(fp_B) ‖ nonce_A ‖ nonce_B ‖ pin_salt
sas_hash  = 33a7dee557f486e0024f598cdf00c03cbc41f5f9f9b2bd06fa59fc43dde4c6ea
uint32_be = 0x33a7dee5 = 866639589
sas       = 866639589 mod 1000000 = "639589"
```
และ MUST ได้ `"639589"` เมื่อสลับ `fp_A` ↔ `fp_B` (symmetry) โดยไม่มีค่าใดที่ derive มาจาก PIN ถูกส่งผ่านเครือข่ายเด็ดขาด

### 18.3 HLC Merge & Clock Drift Check (§10.3 & ADR-008)

| ลำดับ | Local Physical `ts` | A HLC `{l, c, d}` | B HLC `{l, c, d}` | เหตุการณ์ |
|---|---|---|---|---|
| 0 | 1757280000000 | `1757280000000:0:nodeA` | `1757280000000:0:nodeB` | เริ่มต้น |
| 1 | 1757280000100 | `1757280000100:0:nodeA` | `1757280000000:0:nodeB` | A copy → `tick(1757280000100)` ส่ง `l=1757280000100, c=0` |
| 2 | 1757280000050 | `1757280000100:0:nodeA` | `1757280000100:1:nodeB` | B รับที่ `ts=1757280000050` → `merge(A, 1757280000050)` ได้ `l=1757280000100, c=1` |
| 3 | 1757280000100 | `1757280000100:0:nodeA` | `1757280000100:2:nodeB` | B copy ที่ `ts=1757280000100` (ms เดิม) → `tick(1757280000100)` ได้ `c=2` ส่งหา A |
| 4 | 1757280000150 | `1757280000150:0:nodeA` | `1757280000100:2:nodeB` | A รับที่ `ts=1757280000150` → `merge(B, 1757280000150)` physical ก้าวหน้า → `c=0` |
| 5 | 1757280000000 | — | `ClockDriftException` | Malicious peer ส่ง `l=1757280070000` (drift 70s > 60s) → ถูก reject ทันที |

### 18.4 HLC Tie-break & LWW

```
Event X: {origin: "aaaaaaaa-0000-4000-8000-000000000000", hlc: "1757280000000:5:aaaaaaaa-0000-4000-8000-000000000000"}
Event Y: {origin: "bbbbbbbb-0000-4000-8000-000000000000", hlc: "1757280000000:5:bbbbbbbb-0000-4000-8000-000000000000"}

เมื่อเปรียบเทียบ HLC Total Order:
1. l เท่ากัน (1757280000000)
2. c เท่ากัน (5)
3. d tie-breaker: "bbbbbbbb-0000-4000-8000-000000000000" > "aaaaaaaa-0000-4000-8000-000000000000"
ทุกอุปกรณ์ MUST เลือก Event Y เสมอ ไม่ว่าจะได้รับข้อมูลในลำดับใด
```

### 18.5 Size Routing Boundary

| raw size (bytes) | ผลลัพธ์ |
|---|---|
| 32,767 | `inline` |
| 32,768 | `inline` |
| 32,769 | `blob_id` |
| 33,554,432 | `blob_id` |
| 33,554,433 | ไม่ส่ง (`E_PAYLOAD_TOO_LARGE` ถ้ามาจาก peer) |

### 18.6 Path Attack Vectors (NFR-S03 — ต้องถูกบล็อกครบ 13/13)

| # | Input | เหตุผลที่ต้องบล็อก |
|---|---|---|
| V1 | `../../etc/passwd` | parent traversal |
| V2 | `photos/../../secret.txt` | traversal ซ่อนกลาง path |
| V3 | `/etc/passwd` | absolute POSIX |
| V4 | `C:/Windows/System32/evil.dll` | drive letter |
| V5 | `//server/share/x` | UNC / empty component |
| V6 | `..\..\Windows\win.ini` | backslash separator |
| V7 | `file\u0000.txt` | null byte injection |
| V8 | `CON`, `con.txt`, `COM1.log`, `LPT9`, `CONIN$`, `COM¹` | Windows reserved names |
| V9 | `report.` / `report ` | trailing dot/space (Windows) |
| V10 | `a:b.txt` (ADS), `a<b>.txt`, `what?.txt` | reserved characters |
| V11 | `bad\u001Bname.txt` | control characters |
| V12 | `./a`, `a//b`, component ยาว 256 bytes | empty/dot/overlong component |
| V13 | `invoice\u202Etxt.exe`, `\u2066secret\u2069.doc` | Unicode bidi override (ซ่อนนามสกุลจริง) |

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
| S0.1 | TLS 1.3 + mTLS + ECDSA P-256 self-signed + app-layer pinning บน Dart (macOS/Windows/Android) และ `URLSession` (iOS Share Extension) — **ส่วน Dart บน Windows ทดลองแล้ว (PCR-03):** TLS 1.3-only และปฏิเสธ TLS 1.2 ได้, cert ที่ไม่ trusted ทำให้ handshake ล้ม, เพิ่ม trust หลัง bind ได้, `usePrivateKeyBytes` รับ EC PEM — ที่เหลือ: macOS/Android และ iOS `URLSession` | LEAD | ADR-006 (ผ่านการทดสอบข้ามแพลตฟอร์ม Dart ↔ iOS Network.framework ↔ Android Keystore) |
| S0.2 | Android 10–14: Transient Activity อ่าน clipboard จาก QS Tile/Notification ได้จริงบน Pixel/Samsung/Xiaomi; iOS Share Extension เปิด TLS + client cert ภายใต้ 30 MB | MOB | ADR-007 |
| OI-1 | iOS: AppIntent จาก Widget เขียน `UIPasteboard` ได้หรือไม่โดยไม่เปิดแอป (iOS 17+) | MOB | ผลของ S0.2 — ถ้าไม่ได้ Widget เปิดแอปแทน |
| OI-2 | ขนาด `CLIPBOARD_MAX_SIZE` 32 MiB เหมาะกับ RAM มือถือหรือไม่ | NET | ผลวัดใน T1.29 |

---

## 20. Change Log

| Version | Date | การเปลี่ยนแปลง |
|---|---|---|
| 1.0 | 2026-09-08 | เวอร์ชันแรก — frozen สำหรับ Phase 1 |
| 2.0 | 2026-10-12 | **Realign กับ SRS-DC-V1.2:** เพิ่ม traceability (§0.2) และ Capability Tiers (§2.2, `tier` ใน TXT/hello); เพิ่ม `port` ใน TXT ตาม FR-01; stale = ทำเครื่องหมายไม่ใช่ซ่อน (§3.5) + trust classification `identity_changed`; กำหนด Topology/Initiator rule/Close codes (§6); แยก WS frame limit 64 KiB ออกจาก inline threshold 32 KiB (แก้ความขัดแย้งเดิมเรื่อง base64 overhead); เพิ่ม PIN pairing mode + `/pair/confirm` + lockout `E_PAIR_LOCKED`/`E_PAIRING_INVALID` และเลิกส่ง SAS ใน response; นิยาม SAS input แบบ byte-exact พร้อม test vector ที่คำนวณแล้ว; เพิ่ม `POST /api/v1/clipboard` และ `GET /api/v1/clipboard/latest` สำหรับ Tier 2/3 (FR-03B/C); ลบ `clipboard.request_blob` (ดึง blob ผ่าน HTTP ตรง); เพิ่ม payload `clipboard.clear`, `file.cancel`, `file.complete`; Data plane เปลี่ยนเป็น `POST` + `X-Offset` ตาม FR-07 พร้อม resume แบบ chunk-aligned + `last_chunk_sha256` (FR-09); เพิ่ม `manifest` สำหรับโฟลเดอร์ใหญ่; persist Lamport clock; Image wire rules (§11); Platform Channel Contract (§14); Persistence Schemas E-01…E-06 (§15); Path sanitization ครบ 12 attack vectors (NFR-S03) |
| 2.1 | 2026-10-13 | **Protocol & Architectural Alignment (PCR-01):** ปรับ §9.1 และ §9.2 ให้สอดคล้องกับ §5.4 Commit-then-Reveal ครบถ้วน (`/pair/finalize`, `commitment_B`); ปรับ §18.1 เป็น Dual Nonce SAS 160 bytes ("337017"); เปลี่ยน HTTP headers ใน §9.4, §9.5 และ Catch-up ใน §10.7 เป็น `X-DropClip-HLC`; อัปเดต test vectors §18.3 และ §18.4 เป็น HLC Merge & Tie-break; เพิ่ม `MAX_CLOCK_DRIFT` (60s) และ `MIN_SUPPORTED_VERSION` ใน §16; อัปเดต S0.1 ใน §19 เป็น ECDSA P-256 ตาม ADR-006; แก้ไขเลขหัวข้อ duplicate `7.4.12 error` |
| 2.2 | 2026-10-13 | **Review follow-up (PCR-03):** §2.3 อนุญาตส่งต่อ signed revocation token; §9.2 nonce เป็น Base64 ตาม §1; §10.4 แก้ชื่อ `CanUploadToCloudClipboard` และเอา `CLASSIFICATION_NOT_COMPLETE` ออก (ไม่ใช่ sensitivity marker); §12.4 resume ด้วยการ rehash `.part` ใหม่แทนการกู้ hasher state; §13.1 close code `4004`; §15.6 `auto_accept` default = `false` (สอดคล้อง T-E03); §17.3/§18.6 เพิ่ม V13 bidi และ `CONIN$`/`COM¹`; §3.1 Windows ใช้ DNS-SD ของระบบแทน `SO_REUSEADDR`; §4.2 envelope encryption (key ไม่ใช่ hardware-bound); §4.4/§5.4/§9.1 pairing ไม่ใช้ client cert ตามผล S0.1; §13.2 quarantine-then-confirm กันเครื่องที่ถูกขโมย revoke เครื่องจริง; §10.4 เพิ่ม `com.agilebits.onepassword` |