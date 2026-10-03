#!/usr/bin/env python3
"""i18n tooling for the ProMe strings catalog.

The single source of translation truth is
`App/ProMe/Resources/Localizable.xcstrings` (Xcode String Catalog).
This script helps translators and CI work with it from the command line:

    python3 Tools/i18n.py coverage              # stats for every language
    python3 Tools/i18n.py coverage --lang fa    # stats for one language
    python3 Tools/i18n.py missing --lang fa     # keys without a translation
    python3 Tools/i18n.py add ar                # scaffold a new language
    python3 Tools/i18n.py check                 # CI gate (see --help)

`add <code>` inserts every existing key with an empty placeholder entry so
translators only need to fill values (in Xcode or a text editor).

`check` fails (exit 1) when any catalog key lacks the base languages
(en is the source language) and fails when a language that has been
"declared complete" in `complete_languages` below is missing translations.
Update that list when a language reaches 100%.
"""
import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "App" / "ProMe" / "Resources" / "Localizable.xcstrings"

# Languages that must be 100% translated for CI to pass.
complete_languages = ["fa"]


def load() -> dict:
    with open(CATALOG, encoding="utf-8") as handle:
        return json.load(handle)


def save(catalog: dict) -> None:
    with open(CATALOG, "w", encoding="utf-8") as handle:
        json.dump(catalog, handle, ensure_ascii=False, indent=2, sort_keys=True)
        handle.write("\n")


def languages(catalog: dict) -> set[str]:
    codes = set()
    for entry in catalog["strings"].values():
        codes.update((entry.get("localizations") or {}).keys())
    return codes


def keys(catalog: dict) -> list[str]:
    return sorted(catalog["strings"].keys())


def untranslated(catalog: dict, lang: str) -> list[str]:
    missing = []
    for key in keys(catalog):
        entry = catalog["strings"][key]
        unit = (entry.get("localizations") or {}).get(lang, {}).get("stringUnit", {})
        value = unit.get("value", "")
        if unit.get("state") != "translated" or not value.strip():
            missing.append(key)
    return missing


def cmd_coverage(args) -> int:
    catalog = load()
    wanted = [args.lang] if args.lang else sorted(languages(catalog))
    print(f"{'language':<8} {'translated':>10} {'total':>8} {'percent':>8}")
    total = len(keys(catalog))
    for code in wanted:
        missing = len(untranslated(catalog, code))
        done = total - missing
        percent = 100.0 * done / total if total else 0.0
        print(f"{code:<8} {done:>10} {total:>8} {percent:>7.1f}%")
    return 0


def cmd_missing(args) -> int:
    catalog = load()
    for key in untranslated(catalog, args.lang):
        print(key)
    return 0


def cmd_add(args) -> int:
    catalog = load()
    code = args.lang.lower()
    if code == "en":
        print("en is the source language; nothing to add.", file=sys.stderr)
        return 2
    created = 0
    for key in keys(catalog):
        entry = catalog["strings"][key]
        localizations = entry.setdefault("localizations", {})
        if code not in localizations:
            localizations[code] = {
                "stringUnit": {"state": "translated", "value": key}
            }
            created += 1
    save(catalog)
    print(f"language '{code}': scaffolded {created} entries with English "
          f"placeholders — translate them in Xcode or this file, then run "
          f"'python3 Tools/i18n.py coverage --lang {code}' until it reaches 100%.")
    return 0


def cmd_check(args) -> int:
    catalog = load()
    failure = False
    for code in complete_languages:
        missing = untranslated(catalog, code)
        if missing:
            failure = True
            print(f"FAIL: language '{code}' is missing {len(missing)} translation(s):",
                  file=sys.stderr)
            for key in missing[:20]:
                print(f"  {key}", file=sys.stderr)
            if len(missing) > 20:
                print(f"  … and {len(missing) - 20} more", file=sys.stderr)
        else:
            print(f"OK: '{code}' is fully translated "
                  f"({len(keys(catalog))} keys).")
    return 1 if failure else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    coverage = sub.add_parser("coverage", help="translation stats per language")
    coverage.add_argument("--lang", help="limit to one language code")
    coverage.set_defaults(func=cmd_coverage)

    missing = sub.add_parser("missing", help="list keys without a translation")
    missing.add_argument("--lang", required=True)
    missing.set_defaults(func=cmd_missing)

    add = sub.add_parser("add", help="scaffold a new language in the catalog")
    add.add_argument("lang", help="ISO language code, e.g. ar, tr, de")
    add.set_defaults(func=cmd_add)

    check = sub.add_parser("check", help="CI gate for complete languages")
    check.set_defaults(func=cmd_check)

    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
