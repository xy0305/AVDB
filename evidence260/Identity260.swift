import Foundation
enum CatalogueIdentity {
    static func parts(_ raw: String) -> (prefix: String, serial: String)? {
        let text = JRPolicy.foldedCode(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        // Digit-bearing labels require an explicit separator: R18292 is ambiguous.
        let patterns = [#"^([A-Z]{1,4}[0-9]{1,4})[-_ ]([0-9]{2,10})$"#,
                        #"^([0-9]{1,4}[A-Z]{2,12})[-_ ]?([0-9]{2,10})$"#,
                        #"^([A-Z]{2,12})[-_ ]?([0-9]{2,10})$"#]
        for pattern in patterns {
            if let m = JRHTML.matches(pattern, text).first { return (m[1], m[2]) }
        }
        return nil
    }
    static func key(_ raw: String) -> String? {
        guard let p = parts(raw), !p.prefix.hasPrefix("FC2"), let n = UInt64(p.serial), n > 0 else { return nil }
        return p.prefix + "-" + String(n)
    }
    static func withoutLeadingDigits(_ raw: String) -> String? {
        guard let p = parts(raw), p.prefix.first?.isNumber == true else { return nil }
        return key(String(p.prefix.drop(while: { $0.isNumber })) + "-" + p.serial)
    }
    static func matches(_ candidate: String, wanted: String) -> Bool {
        guard let a = key(candidate), let b = key(wanted) else { return false }
        if a == b { return true }
        // Only absent leading digits, never two different numeric namespaces.
        return withoutLeadingDigits(candidate) == b || withoutLeadingDigits(wanted) == a
    }
    static func queryForms(_ number: String) -> [String] {
        guard let p = parts(number) else { return [] }
        var forms = [p.prefix + "-" + p.serial, p.prefix + p.serial]
        if p.prefix.first?.isNumber == true {
            forms.append(String(p.prefix.drop(while: { $0.isNumber })) + "-" + p.serial)
        }
        var seen = Set<String>(); return forms.filter { seen.insert($0).inserted }
    }
}
