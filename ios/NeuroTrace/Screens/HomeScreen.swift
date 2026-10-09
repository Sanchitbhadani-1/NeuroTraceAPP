import SwiftUI

@MainActor
@Observable
final class HomeModel {
    unowned let app: AppModel
    var aboutReference: String? = nil

    init(app: AppModel) { self.app = app }

    func login() {
        app.go(.testing)
    }

    func onShow() {
        Task {
            do {
                let reference = try await app.scoring.value.reference
                let all = reference.brackets["all"]!
                aboutReference = Copy.referenceSentence(referenceN: all.n, bracketKey: "all", deviceMatched: reference.deviceMatched == true)
            } catch {
                aboutReference = nil
            }
        }
    }
}

struct HomeScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p
    @Environment(\.typo) private var typo

    var body: some View {
        let home = app.home
        ScreenView { _ in
            HStack(spacing: 10) {
                MarkView(size: 28)
                Text("NeuroTrace").text(.brand(19))
            }
            .frame(minHeight: 44)

            Hero().padding(.top, 20).fullWidth(.center)

            H1(text: "Measure how you move.", size: 40, lineHeight: 1.08, top: 32)
            Text(Copy.pitch + " " + Copy.tracks).text(.lede).padding(.top, 12)

            VStack(spacing: 10) {
                Btn(title: "Log in") { home.login() }
                Text(Copy.loginNote).text(.sub).multilineTextAlignment(.center).fullWidth(.center)
            }
            .padding(.top, 24)

            Card {
                Text("What it is not").text(.cardTitle)
                Text(Copy.notADiagnosis).text(.body)
            }
            .padding(.top, 24)

            Text("How it works").text(.sectionTitle).padding(.top, 28)
            Card(padding: 0, spacing: 0) {
                // one numbered row per Copy.howSteps
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<Copy.howSteps.count, id: \.self) { i in
                        if i > 0 { Hairline() }
                        HStack(alignment: .top, spacing: 14) {
                            Text("\(i + 1)")
                                .nt(.body(nil, 600, lineHeight: 1.2))
                                .foregroundStyle(p.accent.color)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(p.accentSoft.color))
                            Text(Copy.howSteps[i]).text(.body).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 14)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
            .padding(.top, 12)

            Text("Who you are compared with").text(.sectionTitle).padding(.top, 28)
            if let reference = home.aboutReference {
                Card { Text(reference).text(.body) }.padding(.top, 12)
            }

            LockNote().padding(.top, 24)
            Text(Copy.credit).text(.sub).multilineTextAlignment(.center).fullWidth(.center).padding(.top, 20)
        }
    }
}

private struct Hero: View {
    @Environment(\.palette) private var p
    @Environment(\.typo) private var typo
    @State private var drawn: CGFloat = 0

    var body: some View {
        let size = min(272, max(180, typo.height - 572))
        let inner = size * 0.868
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(p.surface.color)
                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(p.line.color, lineWidth: 1))
                .shadow(color: .black.opacity(0.2), radius: 18, x: 0, y: 18)
            ZStack {
                ArtShape(points: Art.guide).stroke(p.guide.color, lineWidth: 3 * inner / 340)
                ArtShape(points: Art.trace)
                    .trim(from: 0, to: drawn)
                    .stroke(p.accent.color, style: StrokeStyle(lineWidth: 5.5 * inner / 340, lineCap: .round, lineJoin: .round))
            }
            .frame(width: inner, height: inner)
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("A spiral traced by hand over the on-screen guide")
        .onAppear {
            if Motion.reduced() {
                drawn = 1
                return
            }
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 2.6).delay(0.3)) { drawn = 1 }
        }
    }
}
