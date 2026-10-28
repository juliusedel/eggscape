#!/usr/bin/env python3 -I
"""Merges translations into a String Catalog (.xcstrings), keeping everything else as it is.

usage: python3 -I scripts/merge_translations.py App/Resources/Localizable.xcstrings translations.json

translations.json maps a key to one of:
  "English text"                                    plain translation (German is the key itself)
  {"en": "...", "de": "..."}                        explicit German value, for keys like "pause.resume"
  {"en": {"one": "...", "other": "..."},            plural variations; "de" may be a string or plurals too
   "de": {"one": "...", "other": "..."}}
"""
import json
import sys


def unit(value):
    return {"stringUnit": {"state": "translated", "value": value}}


def localization(value):
    if isinstance(value, dict):
        return {"variations": {"plural": {form: unit(text) for form, text in value.items()}}}
    return unit(value)


def main():
    catalog_path, translations_path = sys.argv[1], sys.argv[2]
    with open(catalog_path, encoding="utf-8") as handle:
        catalog = json.load(handle)
    with open(translations_path, encoding="utf-8") as handle:
        translations = json.load(handle)

    strings = catalog.setdefault("strings", {})
    for key, value in translations.items():
        entry = strings.setdefault(key, {})
        localizations = entry.setdefault("localizations", {})
        if isinstance(value, dict) and "en" in value:
            localizations["en"] = localization(value["en"])
            if "de" in value:
                localizations["de"] = localization(value["de"])
        else:
            localizations["en"] = localization(value)

    catalog["strings"] = dict(sorted(strings.items(), key=lambda item: item[0].lower()))
    with open(catalog_path, "w", encoding="utf-8") as handle:
        json.dump(catalog, handle, ensure_ascii=False, indent=2, separators=(",", " : "))
        handle.write("\n")
    print(f"{len(translations)} translations merged, {len(strings)} keys in the catalog")


if __name__ == "__main__":
    main()
