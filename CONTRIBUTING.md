# Contributing to ProMe

Thank you for improving ProMe! This guide covers building, testing and the
project conventions. Translators: see [docs/TRANSLATING.md](docs/TRANSLATING.md).

ProMe is developed by the **free software group**; the original repository is
<https://github.com/javadalmasi/ProMe>. Personal attribution is intentionally
kept out of the product — contributions belong to the group, not individuals.

## Prerequisites

- macOS 14+ with Xcode (latest stable) including the iOS Simulator runtime.
- Python 3 for the localization tooling (`Tools/i18n.py`).

## Build & test

```bash
Tools/build.sh                # build (macOS)
Tools/build.sh test           # all unit tests (macOS)
Tools/build.sh test ios       # tests on an iPhone simulator
Tools/build.sh test ipados    # tests on an iPad simulator
Tools/build.sh build ios      # iOS Simulator build only
```

CI runs the same commands via `.github/workflows/ci.yml`, plus the i18n gate.

## Project layout

```
App/ProMe/               SwiftUI app target (features, navigation, settings)
  App/                   AppModel, formatting helpers, app entry
  Features/<Module>/     One folder per screen (view + its model/editors)
  Navigation/            Route definitions and the animated sidebar
  Settings/              Settings (general, about, sync, backup, diagnostics)
Packages/ProMeDomain/    Pure Swift: money, accounting, calendar, banks
Packages/ProMeData/      Core Data stack, services, sync/crypto
Packages/ProMeDesignSystem/  Fonts, colors, shared components
Tests/DomainTests/       Tests for ProMeDomain
Tests/DataTests/         Tests for ProMeData incl. SecurityTests
Tools/                   build.sh, i18n.py, make_icon.swift
```

## Conventions

- **Language**: code, comments, commit messages and PR titles are English.
- **Swift 6** with strict concurrency: keep UI code `@MainActor`, keep the
  Domain package free of AppKit/UIKit/Core Data imports.
- **Money** is integer minor units (`Money`) — never `Double`.
- **Core Data model**: never edit an existing model version. Add a new
  version under `Packages/ProMeData/Sources/ProMeData/Model/` and set it as
  the current version; lightweight migration handles the rest.
- **User-visible strings** always go through `String(localized:)` and must
  have a Persian (`fa`) entry in `App/ProMe/Resources/Localizable.xcstrings`
  (CI enforces this via `Tools/i18n.py check`).
- **Security-relevant code** lives in `ProMeData/Sync` and needs a test:
  every primitive (crypto, signing, blob format, merge) is covered in
  `Tests/DataTests/SecurityTests.swift`. Keep it that way.

## Commit messages

English, imperative mood, concise subject (`feat: …`, `fix: …`, `docs: …`,
`ci: …`, `i18n: …`, `refactor: …`). Example:

```
feat: add Sheba validation to the account editor
```

## Pull requests

1. Fork / branch from `main`.
2. Make the change with tests where it makes sense.
3. `Tools/build.sh test` must pass; `python3 Tools/i18n.py check` must pass.
4. Open the PR against the original repository with a short English
   description of the what and the why.

## Reporting issues

Open an issue in the original repository. Please include the app version
(Settings → About), the platform (macOS / iOS / iPadOS) and steps to
reproduce. Never attach financial data or snapshots — diagnostics output in
Settings → Diagnostics is deliberately free of amounts.
