# Translating ProMe / ترجمه ProMe

ProMe speaks English (the source language) and Persian (`fa`) today, and is
built to accept any language. This guide shows the whole workflow — no Xcode
required unless you prefer it.

ProMe امروز به انگلیسی (زبان مبدأ) و فارسی صحبت می‌کند و برای پذیرش هر زبان
دیگری ساخته شده است. این راهنما کل مسیر ترجمه را نشان می‌دهد — استفاده از
Xcode اختیاری است.

---

## How i18n works in ProMe / سازوکار i18n در ProMe

- **Single source of truth**: `App/ProMe/Resources/Localizable.xcstrings`
  (the standard Xcode String Catalog). Every user-visible string is a key in
  this JSON file with per-language translations.
- **English keys are the English text**: the key itself is shown when no
  English entry exists, so English needs no maintenance.
- **Automatic availability**: once a language has entries in the catalog and
  the app is rebuilt, it appears automatically in *Settings → General →
  App Language* — no code change needed. The app also flips to RTL
  automatically for RTL languages (Arabic, Hebrew, Urdu, …).
- **Command-line tooling**: `Tools/i18n.py` reports coverage, lists missing
  keys and scaffolds a new language.

---

## Adding a new language (example: Turkish) / افزودن زبان جدید (مثال: ترکی)

### 1. Scaffold the catalog / ساخت زیرساخت در کاتالوگ

```bash
python3 Tools/i18n.py add tr
python3 Tools/i18n.py coverage --lang tr   # 0% — all keys are placeholders
```

Every key now has a `tr` entry pre-filled with the English text as a
placeholder, ready to be replaced.

### 2. Translate / ترجمه کنید

Two options:

- **Xcode**: open `ProMe.xcodeproj`, select
  `App/ProMe/Resources/Localizable.xcstrings`, add Turkish in the language
  list and fill the table. Xcode highlights missing entries.
- **Plain editor**: open the `.xcstrings` JSON, find the `"tr"` entries and
  replace the placeholder values. Keep interpolation placeholders intact:
  `%@` (text), `%lld` (numbers) and positional forms like `%1$@` must stay
  in the translated string, in the order your language needs.

Example entry:

```json
"Daily Tasks": {
  "extractionState": "manual",
  "localizations": {
    "fa": { "stringUnit": { "state": "translated", "value": "کارهای روزانه" } },
    "tr": { "stringUnit": { "state": "translated", "value": "Günlük görevler" } }
  }
}
```

### 3. Check your progress / بررسی پیشرفت

```bash
python3 Tools/i18n.py coverage --lang tr
python3 Tools/i18n.py missing --lang tr   # keys still untranslated
```

### 4. Mark the language complete / اعلام تکمیل زبان

When coverage reaches 100%, add the code to `complete_languages` at the top
of `Tools/i18n.py`:

```python
complete_languages = ["fa", "tr"]
```

From then on, CI fails if any key loses its Turkish translation — your work
can never silently regress.

### 5. Build and send a pull request / بیلد و ارسال

```bash
Tools/build.sh test && python3 Tools/i18n.py check
```

Then open a PR in the original repository
(<https://github.com/javadalmasi/ProMe>) — see [CONTRIBUTING.md](../CONTRIBUTING.md).
Even a partial translation is welcome: send it with the "complete"
step skipped and note the percentage in the PR description.

---

## Translation guidelines / اصول ترجمه

- Keep it short: sidebar labels and buttons wrap badly when translated long.
- Do not translate the brand name **ProMe**.
- Financial terms follow the app's domain: "minor units" is the smallest
  currency unit; "ledger/journal" are accounting terms — translate them
  consistently.
- Persian specifics: use ZWNJ (نیم‌فاصله) correctly («می‌شود»، «حساب‌ها»)،
  Persian digits appear automatically via the digit-style setting — write
  plain numbers in translations.
- Placeholders (`%@`, `%lld`, `%1$@`) are sacred: never remove or rename
  them. Reorder is fine (use `%1$@`-style if the order changes).
- RTL languages need no layout work — the UI mirrors automatically.

---

## FAQ / پرسش‌های پرتکرار

**Q: The app shows English for a string although I translated it.**
The key in code no longer matches the catalog entry (usually a changed
format string). Run `python3 Tools/i18n.py missing --lang <code>` and compare
with the key used in the source.

**Q: Can I translate via an online platform (Weblate/Crowdin)?**
Yes — the catalog is plain JSON at a stable path, so any tool that speaks
the XcStrings/JSON format works. Point it at
`App/ProMe/Resources/Localizable.xcstrings`.
