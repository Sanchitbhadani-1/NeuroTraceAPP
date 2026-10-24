import UIKit

// Gemini through Firebase AI Logic. Firebase holds the Gemini key, and App Check proves the call came from this app.
// Compiles to "not set up" until the Firebase package is added, so builds without it still run, just without the home scan
#if canImport(FirebaseAILogic)
import FirebaseAILogic

@MainActor
enum HomeScanAI {
    // The newest Gemini Flash that Firebase promises to keep until at least May 2027 (their model list, Oct 22 2026).
    // Newer ones are marked short term and can be switched off sooner
    static let modelName = "gemini-3.5-flash"
    static let maxAsk = 8 // cleanIdeas keeps 6, so a few dropped ideas still leave a full list
    // Seconds to wait for Gemini before the scan gives up
    static let timeout = 25.0

    // Cloud starts Firebase, with App Check
    static var ready: Bool { Cloud.ready }

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

    // The prompt says nothing about anyone's health, so no health detail goes to Google with the photo.
    // Returns the model's JSON text, which HomeScanRules.cleanIdeas checks before anything is shown.
    // Throws if Gemini can't be reached in time, and the screen then says so
    static func ideas(_ photo: CGImage) async throws -> String {
        guard let jpeg = UIImage(cgImage: photo).jpegData(compressionQuality: 0.7) else { return "" }
        let model = FirebaseAI.firebaseAI(backend: .googleAI()).generativeModel(
            modelName: modelName,
            generationConfig: GenerationConfig(responseMIMEType: "application/json", responseSchema: schema),
            requestOptions: RequestOptions(timeout: timeout)
        )
        return try await model.generateContent(InlineDataPart(data: jpeg, mimeType: "image/jpeg"), prompt).text ?? ""
    }
}
#else
@MainActor
enum HomeScanAI {
    static let ready = false
    static func ideas(_ photo: CGImage) async throws -> String { "" }
}
#endif
