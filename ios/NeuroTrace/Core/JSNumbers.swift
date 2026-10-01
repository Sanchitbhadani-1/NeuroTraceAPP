import Foundation

// Number helpers that behave exactly like JavaScript's. The measures have to come out identical in
// Swift, JavaScript and Python, so these copy JavaScript's rounding and number printing on purpose

func jsRound(_ x: Double) -> Double {
    if !x.isFinite { return x }
    let f = x.rounded(.down)
    return x - f >= 0.5 ? f + 1 : f
}

func jsNumberString(_ x: Double) -> String {
    if x.isNaN { return "NaN" }
    if x == 0 { return "0" }
    if x.isInfinite { return x < 0 ? "-Infinity" : "Infinity" }
    if x < 0 { return "-" + jsNumberString(-x) }

    let text = "\(x)"
    let parts = text.split(separator: "e", maxSplits: 1)
    let mantissa = String(parts[0])
    let exponent = parts.count > 1 ? Int(parts[1].replacingOccurrences(of: "+", with: "")) ?? 0 : 0
    let halves = mantissa.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
    let whole = String(halves[0]), fraction = halves.count > 1 ? String(halves[1]) : ""
    var digits = Array(whole + fraction)
    var point = whole.count
    while digits.first == "0" { digits.removeFirst(); point -= 1 }
    while digits.last == "0" { digits.removeLast() }
    if digits.isEmpty { return "0" }

    let k = digits.count, n = point + exponent
    let s = String(digits)
    if k <= n && n <= 21 { return s + String(repeating: "0", count: n - k) }
    if 0 < n && n <= 21 { return String(digits[0..<n]) + "." + String(digits[n...]) }
    if -6 < n && n <= 0 { return "0." + String(repeating: "0", count: -n) + s }
    let e = n - 1
    let sign = e < 0 ? "-" : "+"
    if k == 1 { return s + "e" + sign + String(abs(e)) }
    return String(digits[0]) + "." + String(digits[1...]) + "e" + sign + String(abs(e))
}

func toFixed(_ x: Double, _ digits: Int) -> String {
    if x.isNaN { return "NaN" }
    if abs(x) >= 1e21 || x.isInfinite { return jsNumberString(x) }
    let negative = x < 0
    let wide = String(format: "%.\(digits + 30)f", abs(x))
    let halves = wide.split(separator: ".", maxSplits: 1)
    var kept = Array(String(halves[0]) + (halves.count > 1 ? String(halves[1].prefix(digits)) : ""))
    let next = halves.count > 1 ? halves[1].dropFirst(digits).first : nil
    if let next, let d = next.wholeNumberValue, d >= 5 {
        var i = kept.count - 1
        while i >= 0 {
            if kept[i] == "9" { kept[i] = "0"; i -= 1 }
            else { kept[i] = Character(String(kept[i].wholeNumberValue! + 1)); break }
        }
        if i < 0 { kept.insert("1", at: 0) }
    }
    let intCount = kept.count - digits
    var out = String(kept[0..<intCount])
    if digits > 0 { out += "." + String(kept[intCount...]) }
    return (negative ? "-" : "") + out
}
