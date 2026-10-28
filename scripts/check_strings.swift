#!/usr/bin/env swift
// Checks that every localizable string the compiler extracted from the app has an English translation in the
// String Catalog, and lists catalog entries that the code no longer uses.
//
// usage: swift scripts/check_strings.swift <DerivedData dir> App/Resources/Localizable.xcstrings
// (run after a build with SWIFT_EMIT_LOC_STRINGS = YES, e.g. `make build`; `make strings` does both)

import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: check_strings.swift <DerivedData> <Localizable.xcstrings>\n".utf8))
    exit(64)
}

let derivedData = URL(fileURLWithPath: arguments[1], isDirectory: true)
let catalogURL = URL(fileURLWithPath: arguments[2])

struct StringsData: Decodable {
    struct Entry: Decodable {
        let key: String
    }

    let tables: [String: [Entry]]
}

// Collect the keys the Swift compiler extracted for the app target.
var used = Set<String>()
let enumerator = FileManager.default.enumerator(at: derivedData, includingPropertiesForKeys: nil)
while let url = enumerator?.nextObject() as? URL {
    guard url.pathExtension == "stringsdata",
          url.path.contains("/Eggscape.build/"),
          let data = try? Data(contentsOf: url),
          let decoded = try? JSONDecoder().decode(StringsData.self, from: data)
    else { continue }
    for entry in decoded.tables["Localizable", default: []] {
        used.insert(entry.key)
    }
}

guard !used.isEmpty else {
    print("No extracted strings found below \(derivedData.path). Build the app first (make build).")
    exit(1)
}

// Read the catalog.
guard let catalogData = try? Data(contentsOf: catalogURL),
      let catalog = try JSONSerialization.jsonObject(with: catalogData) as? [String: Any],
      let strings = catalog["strings"] as? [String: Any]
else {
    print("Could not read \(catalogURL.path)")
    exit(1)
}

func hasEnglish(_ entry: Any?) -> Bool {
    guard let entry = entry as? [String: Any] else { return false }
    if entry["shouldTranslate"] as? Bool == false {
        return true
    }
    guard let localizations = entry["localizations"] as? [String: Any],
          let english = localizations["en"] as? [String: Any]
    else { return false }
    if let unit = english["stringUnit"] as? [String: Any] {
        return unit["state"] as? String == "translated"
    }
    return english["variations"] != nil
}

let missing = used.filter { !hasEnglish(strings[$0]) }.sorted()
let unused = Set(strings.keys).subtracting(used).sorted()

if !unused.isEmpty {
    print("Catalog entries not used in code (\(unused.count)):")
    unused.forEach { print("  - \($0)") }
}

if missing.isEmpty {
    print("All \(used.count) strings have an English translation.")
} else {
    print("Missing English translations (\(missing.count)):")
    missing.forEach { print("  - \($0)") }
    exit(1)
}
