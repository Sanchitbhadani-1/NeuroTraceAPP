// HOMESCANAI.SWIFT SENDS A PHOTO OF A ROOM TO GEMINI THROUGH FIREBASE AND GETS BACK IDEAS FOR THE ROOM
// WITHOUT THE FIREBASE PACKAGE IT BUILDS A VERSION THAT IS NOT SET UP AND GIVES BACK EMPTY TEXT

import UIKit

// The version with Gemini, built only when the Firebase AI package is there
#if canImport(FirebaseAILogic)
import FirebaseAILogic

// Asks Gemini for ideas about a photo of a room
@MainActor
enum HomeScanAI {

    // The Gemini model to use
    static let modelName = "gemini-3.5-flash"

    // The most ideas to ask Gemini for
    static let maxAsk = 8

    // Seconds to wait for Gemini before the scan gives up
    static let timeout = 25.0

    // True when Firebase is set up
    static var ready: Bool { Cloud.ready }

    // The shape of the answer Gemini has to send back, a room flag, a room name and a list of ideas
    private static let schema = Schema.object(properties: [
        "isRoom": .boolean(),
        "room": .string(),
        "ideas": .array(items: .object(properties: [
            "title": .string(),
            "why": .string(),
            "where": .string(),
            "priority": .enumeration(values: ["high", "medium", "low"]),
        ]), maxItems: maxAsk),
    ])

    // The instructions sent to Gemini with the photo
    private static let prompt = """
        You're helping an older adult make one room easier to move around in. \
        Suggest up to \(maxAsk) specific changes, using only things you can see in this photo, \
        from common home-safety checklists: loose rugs; cords or clutter in walkways; dim lighting \
        and no night lights; stairs without sturdy rails; no bathroom grab bars or non-slip mats; \
        low chairs without arms; everyday things stored out of easy reach. \
        For each idea give a short action as the title (under 10 words), one plain sentence on why it matters, \
        where it is in the photo, and a priority. Write in American English. No medical advice. Never say a change prevents falls \
        or that the room is safe, and don't use the words prevent, guarantee, ensure, safe or improve. \
        If this isn't a photo of a room inside a home, set isRoom to false and return no ideas.
        """

    // Send the photo and the instructions to Gemini and give back its JSON text
    // Throws an error if Gemini can't be reached in time
    static func ideas(_ photo: CGImage) async throws -> String {

        // Turn the photo into a JPEG, or give back empty text if that fails
        guard let jpeg = UIImage(cgImage: photo).jpegData(compressionQuality: 0.7) else { return "" }

        // Set up the model to answer in JSON with the answer shape and the time limit
        let model = FirebaseAI.firebaseAI(backend: .googleAI()).generativeModel(
            modelName: modelName,
            generationConfig: GenerationConfig(responseMIMEType: "application/json", responseSchema: schema),
            requestOptions: RequestOptions(timeout: timeout)
        )

        // Send the photo and the instructions, and give back the text, or empty text if there is none
        return try await model.generateContent(InlineDataPart(data: jpeg, mimeType: "image/jpeg"), prompt).text ?? ""
    }
}

// The version without Firebase, which is never ready and gives back empty text
#else
@MainActor
enum HomeScanAI {
    static let ready = false
    static func ideas(_ photo: CGImage) async throws -> String { "" }
}
#endif
