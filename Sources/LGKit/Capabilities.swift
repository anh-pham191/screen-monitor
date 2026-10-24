public struct Capabilities: Equatable, Sendable {
    public let model: String?
    public let mccsVersion: String?
    /// Feature code to its allowed values; empty when the string lists none.
    public let vcp: [UInt8: [UInt8]]

    public init(model: String?, mccsVersion: String?, vcp: [UInt8: [UInt8]]) {
        self.model = model
        self.mccsVersion = mccsVersion
        self.vcp = vcp
    }

    /// Never fails: monitors return truncated or odd strings, so keep whatever parsed.
    public static func parse(_ text: String) -> Capabilities {
        let chars = Array(text)
        var index = 0
        skipSpaces(chars, &index)
        // The whole string is wrapped in one outer pair of parentheses.
        let body = index < chars.count && chars[index] == "(" ? readGroup(chars, &index) : chars

        var model: String?
        var mccs: String?
        var vcp: [UInt8: [UInt8]] = [:]

        var i = 0
        while i < body.count {
            skipSpaces(body, &i)
            let start = i
            while i < body.count, body[i] != "(", body[i] != " " { i += 1 }
            let name = String(body[start..<i])
            guard i < body.count, body[i] == "(" else { continue }
            let content = readGroup(body, &i)
            switch name {
            case "model": model = String(content)
            case "mccs_ver": mccs = String(content)
            case "vcp": vcp = parseVCP(content)
            default: break
            }
        }
        return Capabilities(model: model, mccsVersion: mccs, vcp: vcp)
    }

    private static func parseVCP(_ chars: [Character]) -> [UInt8: [UInt8]] {
        var result: [UInt8: [UInt8]] = [:]
        var i = 0
        while i < chars.count {
            skipSpaces(chars, &i)
            let start = i
            while i < chars.count, chars[i] != "(", chars[i] != " " { i += 1 }
            let code = UInt8(String(chars[start..<i]), radix: 16)
            var values: [UInt8] = []
            if i < chars.count, chars[i] == "(" {
                values = readGroup(chars, &i).split(separator: " ").compactMap { UInt8(String($0), radix: 16) }
            }
            if let code { result[code] = values }
        }
        return result
    }

    private static func skipSpaces(_ chars: [Character], _ i: inout Int) {
        while i < chars.count, chars[i] == " " { i += 1 }
    }

    /// Reads from the "(" at `i` to its matching ")", leaving `i` just past it.
    /// An unterminated group yields everything up to the end of input.
    private static func readGroup(_ chars: [Character], _ i: inout Int) -> [Character] {
        i += 1
        let start = i
        var depth = 1
        while i < chars.count {
            if chars[i] == "(" { depth += 1 }
            if chars[i] == ")" {
                depth -= 1
                if depth == 0 { break }
            }
            i += 1
        }
        let content = Array(chars[start..<i])
        if i < chars.count { i += 1 }
        return content
    }
}
