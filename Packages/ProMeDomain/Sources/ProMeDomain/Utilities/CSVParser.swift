import Foundation

/// Minimal RFC-4180-style CSV parser: quoted fields, escaped quotes
/// (""), commas and newlines inside quotes, and CRLF endings.
///
/// Note: Swift treats CR+LF as a single Character grapheme, so the
/// newline cases must match "\r\n" explicitly.
public enum CSVParser {
    public static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var field = ""
        var row: [String] = []
        var inQuotes = false
        /// A quote inside a quoted field: could close the field or start
        /// an escaped quote — resolved by looking at the next character.
        var quotePending = false

        func endField() {
            row.append(field)
            field = ""
        }
        func endRow() {
            endField()
            if !(row.count == 1 && row[0].isEmpty) {
                rows.append(row)
            }
            row = []
        }
        func appendUnquoted(_ character: Character) {
            switch character {
            case ",":
                endField()
            case "\r", "\n", "\r\n":
                endRow()
            default:
                field.append(character)
            }
        }

        for character in text {
            if quotePending {
                quotePending = false
                if character == "\"" {
                    field.append("\"")
                } else {
                    inQuotes = false
                    appendUnquoted(character)
                }
                continue
            }
            if inQuotes {
                if character == "\"" {
                    quotePending = true
                } else {
                    field.append(character)
                }
            } else {
                switch character {
                case "\"":
                    inQuotes = true
                default:
                    appendUnquoted(character)
                }
            }
        }
        quotePending = false
        if !field.isEmpty || !row.isEmpty {
            endRow()
        }
        return rows
    }
}
