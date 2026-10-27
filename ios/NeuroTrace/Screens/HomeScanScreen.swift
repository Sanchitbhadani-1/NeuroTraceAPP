// HOMESCANSCREEN.SWIFT IS THE HOME SAFETY SCAN SCREEN
// IT SENDS A PHOTO OF A ROOM TO GEMINI AND SHOWS THE IDEAS THAT COME BACK AS A CHECKLIST

import SwiftUI
import UIKit

// Writes a date as a short month and day
private let scanDayFmt: DateFormatter = {
    let format = DateFormatter()
    format.setLocalizedDateFormatFromTemplate("MMMd")
    return format
}()

// The home safety scan screen, shown full screen from its card
// It shows a message instead of ideas when Gemini can't be reached
struct HomeScanScreen: View {

    // What to do when the screen closes
    let close: () -> Void

    // The colors and text sizes
    @Environment(\.palette) private var p
    @Environment(\.typo) private var typo

    // The last saved scan
    @State private var scan = Store.getHomeScans().last

    // The photo from this visit, kept only while the screen is open
    @State private var photo: UIImage?

    // True once a photo has been scanned on this visit
    @State private var fresh = false

    // Whether a photo is being looked at, and the message to show about it
    @State private var looking = false
    @State private var message: String?

    // Where the photo comes from, the camera or the photo library
    // Also which one is waiting on the consent question, and whether that question is showing
    @State private var source: UIImagePickerController.SourceType?
    @State private var asking: UIImagePickerController.SourceType?
    @State private var askingShown = false

    // Whether the person agreed to send photos to Gemini
    @AppStorage(Store.homeScanConsentKey) private var consented = false

    // True when the screen is at least 760 points wide
    private var wide: Bool { typo.width >= 760 }

    var body: some View {
        ScreenView(maxWidth: wide ? 1000 : 560) { _ in

            // The back link and the title
            BackLink(label: "Care") { close() }
            H1(text: "Home safety scan")

            // How the scan works and the photo buttons
            VStack(alignment: .leading, spacing: 0) {
                if HomeScanAI.ready {
                    Text(Copy.scanHow).text(.lede).fixedSize(horizontal: false, vertical: true).padding(.top, 12)
                    Text(Copy.scanPrivateAI).text(.sub).fixedSize(horizontal: false, vertical: true).padding(.top, 8)

                    // Take a photo shows only when there is a camera, and both buttons are off while a photo is being looked at
                    VStack(spacing: 12) {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Btn(title: "Take a photo", disabled: looking) { choose(.camera) }
                        }
                        Btn(title: "Choose a photo", kind: .secondary, disabled: looking) { choose(.photoLibrary) }
                    }
                    .padding(.top, 24)
                } else {

                    // Without Gemini set up, show a message that the scan isn't set up
                    StatusBox(sentence: Copy.scanNotSetUp, shake: 0)
                }
            }
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)

            // On a wide screen, show the photo and the result side by side
            if let photo, wide {
                HStack(alignment: .top, spacing: 28) {
                    shot(photo).frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 0) { outcome }.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {

                // Otherwise show the photo above the result
                if let photo { shot(photo) }
                outcome
            }
        }
        .background(p.bg.color.ignoresSafeArea())
        // Ask before sending photos to Gemini, and remember the answer when they agree
        .alert("Send photos to Gemini?", isPresented: $askingShown, presenting: asking) { kind in
            Button("Agree") {
                consented = true
                source = kind
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text(Copy.scanConsent)
        }
        // Open the camera or photo library full screen, and look at the photo once one is picked
        .fullScreenCover(isPresented: Binding(get: { source != nil }, set: { if !$0 { source = nil } })) {
            PhotoPicker(source: source ?? .photoLibrary) { image in
                source = nil
                if let image { Task { await look(at: image) } }
            }
            .ignoresSafeArea()
        }
    }

    // Shows that the photo is being looked at, a message about it, or the ideas
    @ViewBuilder private var outcome: some View {

        // A spinner and a line of text while the photo is being looked at
        if looking {
            HStack(spacing: 12) {
                ProgressView()
                Text(Copy.scanLooking).text(.strong)
            }
            .padding(.top, 24)
            .accessibilityElement(children: .combine)
        }

        // The message, if there is one
        if let message { StatusBox(sentence: message, shake: 0).padding(.top, 8) }

        // The ideas, shown when nothing is loading and the scan is new or there is no message
        if let scan, !looking, fresh || message == nil { ideas(scan) }
    }

    // Shows the photo Gemini looked at with a title and a note under it
    private func shot(_ photo: UIImage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your photo").text(.sectionTitle)
            Image(uiImage: photo)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityLabel("Your photo of the room")
            Text(Copy.scanPhotoNote).text(.sub).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 24)
    }

    // Shows the ideas for a scan as a list of rows that can be checked off
    private func ideas(_ scan: HomeScan) -> some View {
        VStack(alignment: .leading, spacing: 12) {

            // The title, which says the date of the scan when it is an older one
            Text(fresh ? "Ideas for this room" : "Your last scan, \(scanDayFmt.string(from: Date(timeIntervalSince1970: Double(scan.ts) / 1000)))")
                .text(.sectionTitle)

            // The room name, then one row per idea with a thin line above it
            Card(padding: 0, spacing: 0) {
                Text(scan.room).text(.cardTitle).padding(20).accessibilityAddTraits(.isHeader)
                ForEach(scan.ideas.indices, id: \.self) { i in
                    let idea = scan.ideas[i]
                    Hairline()

                    // Each row shows the idea, with its place and reason joined by a dot under it
                    CheckRow(text: idea.title, detail: [idea.place, idea.why].filter { !$0.isEmpty }.joined(separator: " · "), checked: idea.done) { toggle(i) }
                }
            }

            // The note under the list and the Done button
            Text(Copy.scanFooter).text(.sub).fixedSize(horizontal: false, vertical: true)
            Btn(title: "Done", kind: .secondary) { close() }.padding(.top, 12)
        }
        .padding(.top, 24)
    }

    // Opens the picker right away if they already agreed, or asks first if they haven't
    private func choose(_ kind: UIImagePickerController.SourceType) {
        if consented { return source = kind }
        asking = kind
        askingShown = true
    }

    // Checks or unchecks an idea and saves the change into the last saved scan
    private func toggle(_ i: Int) {
        guard var now = scan else { return }
        now.ideas[i].done.toggle()
        scan = now

        // Replace the last saved scan with the changed one
        var all = Store.getHomeScans()
        if !all.isEmpty { all[all.count - 1] = now }
        Store.setHomeScans(all)
    }

    // Sends a photo to Gemini and shows the ideas or a message
    private func look(at image: UIImage) async {

        // Clear the last result and say that the photo is being looked at
        message = nil
        fresh = false
        looking = true
        announce(Copy.scanLooking)

        // When this finishes, stop loading and read out the message or how many ideas there are
        defer {
            looking = false
            announce(message ?? scan.map { s in "\(s.ideas.count) \(s.ideas.count == 1 ? "idea" : "ideas") for the \(s.room.lowercased())" } ?? "")
        }

        // Turn the photo upright, or show a message if it can't be read
        guard let picture = Self.upright(image) else {
            message = Copy.scanUnreadable
            return
        }
        photo = UIImage(cgImage: picture)

        // Ask Gemini for ideas and clean up its answer, and print the error if it doesn't answer
        var r: HomeScanResult?
        do {
            let text = try await HomeScanAI.ideas(picture)
            r = HomeScanRules.cleanIdeas(raw: text)
        } catch {
            print("NeuroTrace: Gemini didn't answer", error)
        }

        // With no answer or one that can't be read, show the offline message
        guard let r, r.status != "unreadable" else {
            message = Copy.scanOffline
            return
        }

        // Save and show the ideas when the answer is ok, or show a message for a photo that isn't a room or has no ideas
        switch r.status {
        case "ok":
            let saved = HomeScan(ts: Int(Date().timeIntervalSince1970 * 1000), room: r.room, ideas: r.ideas)
            Store.setHomeScans(Store.getHomeScans() + [saved])
            scan = saved
            fresh = true
        case "notRoom": message = Copy.scanNotRoom
        default: message = Copy.scanEmpty
        }
    }

    // Reads text out loud to screen reader users, skipping empty text
    private func announce(_ text: String) {
        if !text.isEmpty { UIAccessibility.post(notification: .announcement, argument: text) }
    }

    // Redraws the photo upright with its long side at most 1024 pixels, which leaves out the photo's extra data like GPS
    static func upright(_ image: UIImage, longSide: CGFloat = 1024) -> CGImage? {

        // Work out the new size, never making the photo bigger
        let scale = min(1, longSide / max(image.size.width, image.size.height, 1))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        // Draw the photo at that size at one pixel per point
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }.cgImage
    }
}


// Opens the camera or the photo library and hands back the picked photo
struct PhotoPicker: UIViewControllerRepresentable {

    // Camera or photo library, and what to do with the photo, or nil if they cancel
    let source: UIImagePickerController.SourceType
    let done: (UIImage?) -> Void

    // Make the picker and connect it to the coordinator
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = source
        picker.delegate = context.coordinator
        return picker
    }

    // Does nothing when the view updates
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    // Make the coordinator that hears back from the picker
    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    // Hears back from the picker and passes the photo on
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {

        // What to do with the photo
        let done: (UIImage?) -> Void
        init(done: @escaping (UIImage?) -> Void) { self.done = done }

        // Pass on the picked photo
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            done(info[.originalImage] as? UIImage)
        }

        // Pass on nil when they cancel
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { done(nil) }
    }
}
