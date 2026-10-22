import Foundation

// MARK: - LenientJSON
// Parses the JSON object an on-device model returns, repairing the structural slips
// Gemma 4 E2B makes on long structured outputs (bench/results/phase2-diag-2026-10-21.md):
// an array closed with `}`, a string missing its closing quote before a newline,
// a missing final `}`. Values are never changed; only brackets, quotes and trailing
// commas are added, swapped or removed, and a key left without a value is dropped.

nonisolated enum LenientJSON {

    struct Result {
        /// Parsed top-level value, or nil when the repaired text still is not JSON.
        let object: Any?
        /// The text handed to JSONSerialization after repair.
        let candidate: String
        /// One entry per repair applied, e.g. "swap_closer".
        let fixes: [String]
        let error: Error?

        var dictionary: [String: Any]? { object as? [String: Any] }

        /// "swap_closer:2,close_string:1" for one-line log records.
        var fixSummary: String {
            var counts: [String: Int] = [:]
            fixes.forEach { counts[$0, default: 0] += 1 }
            return counts.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: ",")
        }
    }

    static func parse(_ text: String) -> Result {
        let stripped = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
        guard let start = stripped.firstIndex(where: { $0 == "{" || $0 == "[" }) else {
            return decode(stripped.trimmingCharacters(in: .whitespacesAndNewlines), fixes: [])
        }
        let (balanced, fixes) = balance(stripped[start...])
        return decode(balanced, fixes: fixes)
    }

    private static func decode(_ candidate: String, fixes: [String]) -> Result {
        guard let data = candidate.data(using: .utf8) else {
            return Result(object: nil, candidate: candidate, fixes: fixes, error: nil)
        }
        do {
            let object = try JSONSerialization.jsonObject(with: data)
            return Result(object: object, candidate: candidate, fixes: fixes, error: nil)
        } catch {
            return Result(object: nil, candidate: candidate, fixes: fixes, error: error)
        }
    }

    /// Single pass over the text from the first `{` or `[`, tracking string state and a
    /// bracket stack. Stops once the top-level value closes, so trailing prose is dropped.
    private static func balance(_ text: Substring) -> (String, [String]) {
        let characters = Array(text)
        var out = ""
        var stack: [Character] = []
        var fixes: [String] = []
        var inString = false
        var escaped = false

        for (index, ch) in characters.enumerated() {
            if inString {
                if escaped {
                    escaped = false
                } else if ch == "\\" {
                    escaped = true
                } else if ch == "\"" {
                    inString = false
                } else if ch.isNewline {
                    // JSON strings cannot hold a raw newline. If JSON structure follows, the
                    // model dropped the closing quote; otherwise it meant a line break
                    // (e.g. a markdown note), so escape it.
                    let next = characters[(index + 1)...].first { !$0.isWhitespace }
                    if next == nil || "}],\"".contains(next!) {
                        out.append("\"")
                        inString = false
                        fixes.append("close_string")
                    } else {
                        out.append("\\n")
                        fixes.append("escape_newline")
                        continue
                    }
                }
                out.append(ch)
                continue
            }

            switch ch {
            case "\"":
                inString = true
            case "{":
                stack.append("}")
            case "[":
                stack.append("]")
            case "}", "]":
                guard let expected = stack.popLast() else {
                    fixes.append("drop_closer")
                    continue
                }
                if ch != expected { fixes.append("swap_closer") }
                if expected == "}", removeDanglingKey(&out) { fixes.append("dangling_key") }
                if removeTrailingComma(&out) { fixes.append("trailing_comma") }
                out.append(expected)
                if stack.isEmpty { return (out, fixes) }
                continue
            default:
                break
            }
            out.append(ch)
        }

        if inString {
            out.append("\"")
            fixes.append("close_string")
        }
        while let closer = stack.popLast() {
            if closer == "}", removeDanglingKey(&out) { fixes.append("dangling_key") }
            if removeTrailingComma(&out) { fixes.append("trailing_comma") }
            out.append(closer)
            fixes.append("append_closer")
        }
        return (out, fixes)
    }

    /// Removes a key with no value just before an object's `}`:
    /// `{"unit":"%",""}` -> `{"unit":"%"}`. A string right after `{` or `,` is in key position.
    private static func removeDanglingKey(_ out: inout String) -> Bool {
        guard let match = out.range(of: #"[{,]\s*"(?:[^"\\]|\\.)*"\s*$"#, options: .regularExpression) else { return false }
        let keyStart = out[match.lowerBound] == "," ? match.lowerBound : out.index(after: match.lowerBound)
        out.removeSubrange(keyStart..<out.endIndex)
        return true
    }

    /// Removes a `,` (plus whitespace after it) at the end of `out`. Returns true if removed.
    private static func removeTrailingComma(_ out: inout String) -> Bool {
        var end = out.endIndex
        while end > out.startIndex {
            let previous = out.index(before: end)
            if out[previous].isWhitespace {
                end = previous
                continue
            }
            guard out[previous] == "," else { return false }
            out.removeSubrange(previous..<out.endIndex)
            return true
        }
        return false
    }
}
