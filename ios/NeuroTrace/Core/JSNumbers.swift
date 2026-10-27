// JSNUMBERS.SWIFT ROUNDS AND PRINTS NUMBERS THE SAME WAY JAVASCRIPT DOES
// IT COPIES JAVASCRIPT'S ROUNDING, NUMBER PRINTING AND TOFIXED

import Foundation

// Round to the nearest whole number, with halves going up, like Math.round
func jsRound(_ x: Double) -> Double {

    // Give back NaN and infinity as they are
    if !x.isFinite { return x }

    // Round down, then add 1 if the part cut off was a half or more
    let f = x.rounded(.down)
    return x - f >= 0.5 ? f + 1 : f
}

// Turn a number into text the same way JavaScript's String(number) does
func jsNumberString(_ x: Double) -> String {

    // Handle NaN, zero, infinity and negative numbers first
    if x.isNaN { return "NaN" }
    if x == 0 { return "0" }
    if x.isInfinite { return x < 0 ? "-Infinity" : "Infinity" }
    if x < 0 { return "-" + jsNumberString(-x) }

    // Split Swift's text for the number into the digits and the power of ten after "e"
    let text = "\(x)"
    let parts = text.split(separator: "e", maxSplits: 1)
    let mantissa = String(parts[0])
    let exponent = parts.count > 1 ? Int(parts[1].replacingOccurrences(of: "+", with: "")) ?? 0 : 0

    // Join the digits before and after the point, and remember where the point was
    let halves = mantissa.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
    let whole = String(halves[0]), fraction = halves.count > 1 ? String(halves[1]) : ""
    var digits = Array(whole + fraction)
    var point = whole.count

    // Take off zeros at the start and the end of the digits
    while digits.first == "0" { digits.removeFirst(); point -= 1 }
    while digits.last == "0" { digits.removeLast() }
    if digits.isEmpty { return "0" }

    // k is how many digits there are and n is where the point goes
    let k = digits.count, n = point + exponent
    let s = String(digits)

    // A whole number up to 21 digits long, with zeros added at the end
    if k <= n && n <= 21 { return s + String(repeating: "0", count: n - k) }

    // A number with the point inside the digits
    if 0 < n && n <= 21 { return String(digits[0..<n]) + "." + String(digits[n...]) }

    // A small number with up to 6 zeros after the point
    if -6 < n && n <= 0 { return "0." + String(repeating: "0", count: -n) + s }

    // Anything else is written with "e" and a signed power of ten
    let e = n - 1
    let sign = e < 0 ? "-" : "+"
    if k == 1 { return s + "e" + sign + String(abs(e)) }
    return String(digits[0]) + "." + String(digits[1...]) + "e" + sign + String(abs(e))
}

// Write a number with a set count of digits after the point, like JavaScript's toFixed
func toFixed(_ x: Double, _ digits: Int) -> String {

    // Give back NaN, infinity and very large numbers the way String(number) writes them
    if x.isNaN { return "NaN" }
    if abs(x) >= 1e21 || x.isInfinite { return jsNumberString(x) }
    let negative = x < 0

    // Write the number with 30 extra digits, then keep only the digits asked for
    let wide = String(format: "%.\(digits + 30)f", abs(x))
    let halves = wide.split(separator: ".", maxSplits: 1)
    var kept = Array(String(halves[0]) + (halves.count > 1 ? String(halves[1].prefix(digits)) : ""))
    let next = halves.count > 1 ? halves[1].dropFirst(digits).first : nil

    // If the next digit is 5 or more, round up, carrying through any 9s
    if let next, let d = next.wholeNumberValue, d >= 5 {
        var i = kept.count - 1
        while i >= 0 {
            if kept[i] == "9" { kept[i] = "0"; i -= 1 }
            else { kept[i] = Character(String(kept[i].wholeNumberValue! + 1)); break }
        }

        // Add a 1 at the front if every digit was a 9
        if i < 0 { kept.insert("1", at: 0) }
    }

    // Put the point back in and add the minus sign for negative numbers
    let intCount = kept.count - digits
    var out = String(kept[0..<intCount])
    if digits > 0 { out += "." + String(kept[intCount...]) }
    return (negative ? "-" : "") + out
}
