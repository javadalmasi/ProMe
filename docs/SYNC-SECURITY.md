# Sync security design

This document describes how ProMe's encrypted multi-device sync works and
why each mechanism is there. All code lives in
`Packages/ProMeData/Sources/ProMeData/Sync/` and every mechanism is covered
by `Tests/DataTests/SecurityTests.swift`.

## Threat model

| Adversary | Result |
|---|---|
| Storage provider / anyone with bucket access | Sees only ciphertext and signed manifests. No data, no amounts. |
| Password guesser | Master key is wrapped with PBKDF2-HMAC-SHA256 (600 000 iterations); wrong password fails AES-GCM authentication. |
| Bucket tamperer (writes/edits objects) | Snapshot signatures fail (Ed25519) and ciphertext fails AES-GCM authentication; sync refuses the blob. |
| Cross-device replay (moving a blob between devices) | The receiving device compares the blob header's public key with the manifest's — mismatch is rejected. Additional data binds ciphertext to the exact header bytes. |
| Compromised single device | Can read/modify its own data and sign snapshots (inherent to end-user sync), but cannot decrypt other devices' past snapshots without the master key and cannot forge the other devices' signatures. |

## Keys

1. **Master key** — 32 random bytes (`SecRandomCopyBytes`). Encrypts every
   snapshot payload with AES-GCM. Lives in the device keychain
   (`kSecClassGenericPassword`, accessible after first unlock).
2. **Password-wrapped copy** — the master key wrapped with
   `PBKDF2-HMAC-SHA256(password, salt, 600k)` and AES-GCM, stored as
   `vault/keywrap.json` in the bucket. This is the *only* credential that
   lets a new device join: the password is never stored anywhere.
3. **Device signing keypair** — Curve25519/Ed25519, generated per device,
   private seed in the keychain, public key in the device manifest.

## Objects in the bucket

```
<prefix>/vault/keywrap.json                     password-wrapped master key
<prefix>/manifests/<device-uuid>.json           device identity + public key + latest snapshot path
<prefix>/snapshots/<device-uuid>/<ms>.promeball sealed+signed snapshot
```

## Blob format

```
"PROMESYNC" (9 bytes) | version (1) | headerLen (4 LE) | header JSON | ciphertext | signature (64)
```

- `header` = device id, device name, Ed25519 public key, timestamp, schema version.
- `ciphertext` = AES-GCM (nonce‖ciphertext‖tag) of the JSON snapshot, with
  **additional data = magic‖version‖header** — the ciphertext is
  cryptographically bound to its header.
- `signature` = Ed25519 over everything before it, verified **before** any
  decryption is attempted.

## Sync flow

- **Create vault** (first device): generate master key → wrap with password →
  upload `keywrap.json` → keep master key locally.
- **Join vault** (new device): download `keywrap.json` → unwrap with the
  user's password → store master key locally.
- **Push**: export every synced entity + deletion log from Core Data
  (`SnapshotEngine`), seal + sign the blob, upload, update the device
  manifest.
- **Pull**: list other devices' manifests, verify manifest public key against
  the blob header, verify signature, decrypt, then merge.

## Merge semantics

- Every synced entity is keyed by UUID. Entities with `updatedAt` merge
  last-writer-wins; insert-only entities (e.g. payments) keep the local row.
- Deletions are recorded as `DeletionLog` tombstones by the persistence
  controller on every successful save; a remote tombstone deletes the local
  row unless the local row was modified after the deletion. Tombstones older
  than 90 days are pruned.
- Derived ledger data (LedgerAccount/Journal/LedgerLine) is rebuilt by the
  posting engine and deliberately not synced.

## Testing

`SecurityTests` covers: PBKDF2 determinism + published vector, wrap/unwrap
roundtrip and wrong-password rejection, AES-GCM tamper/AAD/key rejection,
Ed25519 verification and forgery failure, blob roundtrip/tamper/spoof/corruption,
keychain roundtrip, the AWS-documented SigV4 vector, canonical query/path
encoding, export/import roundtrip across two stores, LWW conflict resolution
and tombstone propagation.
