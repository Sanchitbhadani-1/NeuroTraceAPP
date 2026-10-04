import Foundation

// Create an error struct with localized error protocols (be able to give a message) and equatable protocol (be able to determine equality)
struct NTError: LocalizedError, Equatable {
    var message: String
    init(_ message: String) {
        self.message = message
    }

    // Make errorDescription = the message
    var errorDescription: String? {
        message
    }
}

// Create a setting called forExport that determines whether something is for export or not
extension CodingUserInfoKey {
    static let forExport = CodingUserInfoKey(rawValue: "neurotrace.forExport")!
}

// Create the basic variables used in a sample, codable and equatable are the protocols for encoding and decoding, and checking equality, respectively
struct Sample: Codable, Equatable {
    var t: Double
    var x: Double
    var y: Double
    var pressure: Double = 0
    var tiltX: Double = 0
    var tiltY: Double = 0

    // Explicitly create the CodingKeys enum
    enum CodingKeys: String, CodingKey {
        case t
        case x
        case y
        case pressure
        case tiltX
        case tiltY
    }
}

// Rewrite the decoding process rather than using Swift's built-in decoder. Give instructions on how to decode a JSON format sample
extension Sample {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        t = try c.decode(Double.self, forKey: .t)
        x = try c.decode(Double.self, forKey: .x)
        y = try c.decode(Double.self, forKey: .y)
        pressure = try c.decodeIfPresent(Double.self, forKey: .pressure) ?? 0
        tiltX = try c.decodeIfPresent(Double.self, forKey: .tiltX) ?? 0
        tiltY = try c.decodeIfPresent(Double.self, forKey: .tiltY) ?? 0
    }
}

// Create the Trace type, which holds an array of samples
struct Trace: Codable, Equatable {
    var task: String
    var hand: String?
    var inputType: String?
    var deviceLabel: String
    var samples: [Sample]
}
