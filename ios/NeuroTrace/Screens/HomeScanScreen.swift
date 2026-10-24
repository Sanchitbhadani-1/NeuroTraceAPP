import SwiftUI
import UIKit

private let scanDayFmt: DateFormatter = {
    let format = DateFormatter()
    format.setLocalizedDateFormatFromTemplate("MMMd")
    return format
}()

// Shown full screen from its card. Gemini looks at the photo and suggests ideas. If Gemini can't be
// reached, the screen says so and that photo gets no ideas
struct HomeScanScreen: View {
    let close: () -> Void
    @Environment(\.palette) private var p
    @Environment(\.typo) private var typo
    @State private var scan = Store.getHomeScans().last
    // The photo from this visit, shown with Gemini's answer. Never saved, and gone once the screen closes
    @State private var photo: UIImage?
    // True once a photo has been scanned on this visit, so the list isn't an older one
    @State private var fresh = false
    @State private var looking = false
    @State private var message: String?
    @State private var source: UIImagePickerController.SourceType?
    @State private var asking: UIImagePickerController.SourceType?
    @State private var askingShown = false
    // Whether the person agreed to send photos to Gemini. Asked before the first photo, and Delete all my data clears it
    @AppStorage(Store.homeScanConsentKey) private var consented = false

    // The photo goes beside Gemini's answer when there's room, and above it when there isn't
    private var wide: Bool { typo.width >= 760 }

    var body: some View {
        ScreenView(maxWidth: wide ? 1000 : 560) { _ in
            BackLink(label: "Care") { close() }
            H1(text: "Home safety scan")
            VStack(alignment: .leading, spacing: 0) {
                if HomeScanAI.ready {
                    Text(Copy.scanHow).text(.lede).fixedSize(horizontal: false, vertical: true).padding(.top, 12)
                    Text(Copy.scanPrivateAI).text(.sub).fixedSize(horizontal: false, vertical: true).padding(.top, 8)
                    VStack(spacing: 12) {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Btn(title: "Take a photo", disabled: looking) { choose(.camera) }
                        }
                        Btn(title: "Choose a photo", kind: .secondary, disabled: looking) { choose(.photoLibrary) }
                    }
                    .padding(.top, 24)
                } else {
                    // A build without Firebase has no Gemini, so there's nothing to scan with
                    StatusBox(sentence: Copy.scanNotSetUp, shake: 0)
                }
            }
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            if let photo, wide {
                HStack(alignment: .top, spacing: 28) {
                    shot(photo).frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 0) { outcome }.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                if let photo { shot(photo) }
                outcome
            }
        }
        .background(p.bg.color.ignoresSafeArea())
        .alert("Send photos to Gemini?", isPresented: $askingShown, presenting: asking) { kind in
            Button("Agree") {
                consented = true
                source = kind
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text(Copy.scanConsent)
        }
        .fullScreenCover(isPresented: Binding(get: { source != nil }, set: { if !$0 { source = nil } })) {
            PhotoPicker(source: source ?? .photoLibrary) { image in
                source = nil
                if let image { Task { await look(at: image) } }
            }
            .ignoresSafeArea()
        }
    }

    // Looking at the photo, a message about it, or the ideas
    @ViewBuilder private var outcome: some View {
        if looking {
            HStack(spacing: 12) {
                ProgressView()
                Text(Copy.scanLooking).text(.strong)
            }
            .padding(.top, 24)
            .accessibilityElement(children: .combine)
        }
        if let message { StatusBox(sentence: message, shake: 0).padding(.top, 8) }
        // An older list is hidden while a new photo is read or couldn't be used, so it isn't
        // mistaken for ideas about that photo
        if let scan, !looking, fresh || message == nil { ideas(scan) }
    }

    // The photo Gemini looked at, so a screenshot shows the room and its ideas together
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

    private func ideas(_ scan: HomeScan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(fresh ? "Ideas for this room" : "Your last scan, \(scanDayFmt.string(from: Date(timeIntervalSince1970: Double(scan.ts) / 1000)))")
                .text(.sectionTitle)
            Card(padding: 0, spacing: 0) {
                Text(scan.room).text(.cardTitle).padding(20).accessibilityAddTraits(.isHeader)
                ForEach(scan.ideas.indices, id: \.self) { i in
                    let idea = scan.ideas[i]
                    Hairline()
                    CheckRow(text: idea.title, detail: [idea.place, idea.why].filter { !$0.isEmpty }.joined(separator: " · "), checked: idea.done) { toggle(i) }
                }
            }
            Text(Copy.scanFooter).text(.sub).fixedSize(horizontal: false, vertical: true)
            Btn(title: "Done", kind: .secondary) { close() }.padding(.top, 12)
        }
        .padding(.top, 24)
    }

    // Asks before the first photo goes to Gemini. Cancel sends nothing, and the next photo asks again
    private func choose(_ kind: UIImagePickerController.SourceType) {
        if consented { return source = kind }
        asking = kind
        askingShown = true
    }

    private func toggle(_ i: Int) {
        guard var now = scan else { return }
        now.ideas[i].done.toggle()
        scan = now
        var all = Store.getHomeScans()
        if !all.isEmpty { all[all.count - 1] = now }
        Store.setHomeScans(all)
    }

    private func look(at image: UIImage) async {
        message = nil
        fresh = false
        looking = true
        announce(Copy.scanLooking)
        defer {
            looking = false
            announce(message ?? scan.map { s in "\(s.ideas.count) \(s.ideas.count == 1 ? "idea" : "ideas") for the \(s.room.lowercased())" } ?? "")
        }
        guard let picture = Self.upright(image) else {
            message = Copy.scanUnreadable
            return
        }
        photo = UIImage(cgImage: picture)
        var r: HomeScanResult?
        do {
            let text = try await HomeScanAI.ideas(picture)
            r = HomeScanRules.cleanIdeas(raw: text)
        } catch {
            print("NeuroTrace: Gemini didn't answer", error)
        }
        // No answer, or one that couldn't be read, means no ideas for this photo
        guard let r, r.status != "unreadable" else {
            message = Copy.scanOffline
            return
        }
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

    private func announce(_ text: String) {
        if !text.isEmpty { UIAccessibility.post(notification: .announcement, argument: text) }
    }

    // Redrawn upright at 1024 px max, which also drops the photo's metadata (GPS and so on)
    static func upright(_ image: UIImage, longSide: CGFloat = 1024) -> CGImage? {
        let scale = min(1, longSide / max(image.size.width, image.size.height, 1))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }.cgImage
    }
}

// Camera or photo library. The library runs outside the app, so it needs no photo permission
struct PhotoPicker: UIViewControllerRepresentable {
    let source: UIImagePickerController.SourceType
    let done: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = source
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let done: (UIImage?) -> Void
        init(done: @escaping (UIImage?) -> Void) { self.done = done }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            done(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { done(nil) }
    }
}
