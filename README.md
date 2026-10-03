# ProMe

[![CI](https://github.com/javadalmasi/ProMe/actions/workflows/ci.yml/badge.svg)](https://github.com/javadalmasi/ProMe/actions/workflows/ci.yml)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

**Developed by the free software group.**
Original repository: **https://github.com/javadalmasi/ProMe**

A native Apple personal suite (macOS + iOS + iPadOS) built with Swift 6 / SwiftUI / Core Data / Swift Charts.
ProMe is more than accounting — it is a single home for your money **and** your personal life: daily tasks, a
professional Jalali calendar, appointments with hourly reminders, alerts, a daily activity log, private notes,
saved places (OpenStreetMap) and full bookkeeping for personal & small-business finance.

> **ProMe** مجموعه شخصی شماست: پول و زندگی، یکجا — حسابداری کامل + کارهای روزانه، تقویم شمسی، قرارها، هشدارها،
> یادداشت‌ها، مکان‌ها و همگام‌سازی رمزنگاری‌شده بین دستگاه‌ها. کاملاً فارسی و راست‌چین با فونت متن‌باز
> [شبنم](https://github.com/rastikerdar/shabnam-font).

## Features

- **My Life** — daily tasks (priority, repeat, reminders), Jalali month calendar with day markers and agenda,
  appointments with precise hourly alerts, alerts (once/daily/weekly/monthly), daily activity log, private
  notes (pin + colors), places saved from OpenStreetMap with map preview.
- **Money** — double-entry accounting engine (unbalanced entries are impossible), transactions with Quick
  Entry ⌘N, transfers, budgets, recurring payments with catch-up, CSV import wizard with duplicate detection
  and smart categorization, reports (cash flow, category, net worth) with CSV export, backup/restore.
- **Iranian banks** — 26 banks & credit institutions with brand-tinted vector logos, card BIN auto-detection,
  Luhn card validation and ISO-13616 Sheba (IBAN) validation with bank-code detection.
- **Encrypted multi-device sync** — snapshots over any S3-compatible bucket (AWS, Wasabi, MinIO, ArvanCloud…),
  encrypted with AES-GCM using a password-wrapped master key (PBKDF2-HMAC-SHA256, 600k iterations) and signed
  per device with Ed25519. Design details: [docs/SYNC-SECURITY.md](docs/SYNC-SECURITY.md).
- **International** — English + Persian out of the box, full RTL, Persian digits and Jalali calendar.
  New languages are welcome — see [docs/TRANSLATING.md](docs/TRANSLATING.md).
- **Free software** — GPL-3.0-or-later. Translations, bug reports and patches are welcome.

## Build & Test

Requirements: Xcode with the iOS Simulator runtime (for the iOS destination) and macOS 14+.

```bash
Tools/build.sh                # build (macOS)
Tools/build.sh test           # run all test targets (macOS)
Tools/build.sh build ios      # build for iOS Simulator
Tools/build.sh test ios       # run tests on an iPhone simulator
Tools/build.sh test ipados    # run tests on an iPad simulator
open ProMe.xcodeproj          # open in Xcode (⌘R to run)
```

Localization tooling:

```bash
python3 Tools/i18n.py coverage     # translation progress per language
python3 Tools/i18n.py check        # CI gate (complete languages must be 100%)
python3 Tools/i18n.py add tr       # scaffold a new language
```

The sandboxed store lives at `~/Library/Containers/app.prome/Data/Library/Application Support/ProMe/ProMe.sqlite`
(a pre-rename `ProBill` store is migrated automatically on first launch).

## Releases

GitHub Actions builds and packages the app automatically:

- **CI** (`.github/workflows/ci.yml`) — macOS unit tests, iOS Simulator tests and the i18n gate on every push/PR.
- **Release** (`.github/workflows/release.yml`) — on a `v*` tag: a zipped `.app` + DMG for macOS and an unsigned
  `.ipa`/archive for iOS, attached to the GitHub release.

Create a release with:

```bash
git tag v0.1.0 && git push origin v0.1.0
```

## Architecture

Three local Swift packages keep the layers honest:

| Package | Depends on | Contains |
|---|---|---|
| `ProMeDomain` | nothing | Money & currency, enums, errors, accounting engine (JournalBuilder, ChartOfAccounts), Persian calendar, Iranian bank registry, card/Sheba validators |
| `ProMeData` | Domain | Core Data stack (schema v5, 29 entities), managed objects, services, sync (crypto, SigV4 S3 client, snapshot engine) |
| `ProMeDesignSystem` | Domain | Shabnam font loading, color/spacing tokens, Card, AmountText, EmptyState, BankLogo |

The `ProMe` app target contains the features (View + model), navigation, settings and the strings catalog.

Key rules:

- Money is always integer minor units (`Money`) — never floating point.
- Ledger lines are only ever produced by `JournalBuilder`, which refuses unbalanced journals; transfers, owner
  contributions and loans can therefore never leak into income/expense reports.
- Dates are stored as standard `Date`; Jalali rendering happens only in the presentation layer.
- Model changes are made by adding a new model version under `Packages/ProMeData/Sources/ProMeData/Model/`,
  never by editing existing versions (v1–v4 stay for lightweight migration from older installs).
- Security code is centralized in `ProMeData/Sync`; `Tests/DataTests/SecurityTests.swift` covers every primitive.

## Contributing

Developer guide: [CONTRIBUTING.md](CONTRIBUTING.md) · Translator guide: [docs/TRANSLATING.md](docs/TRANSLATING.md)

## License

Copyright (C) 2026 the free software group.

This program is free software: you can redistribute it and/or modify it under the terms of the
GNU General Public License as published by the Free Software Foundation, either version 3 of the
License or (at your option) any later version. See [LICENSE](LICENSE).
