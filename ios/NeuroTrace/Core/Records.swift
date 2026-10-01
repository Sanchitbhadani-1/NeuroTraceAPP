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
