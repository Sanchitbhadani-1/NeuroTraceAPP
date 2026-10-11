import SwiftUI

struct TestingScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.typo) private var typo
    @Environment(\.palette) private var p

    var body: some View {
        ScreenView(maxWidth: typo.width >= 900 ? 760 : 560, tabbed: true, titled: true) { _ in
            H1(text: "Testing")
            Text(Copy.testingBlurb).text(.lede).padding(.top, 10)
            Card(spacing: 16) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Spiral check-in").text(.cardTitle)
                        Text(Copy.checkinBlurb).text(.sub).fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    MiniArt()
                }
                Btn(title: "Start a check-in") { app.go(.about) }
            }
            .padding(.top, 24)
        }
    }
}

struct ErrorScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p

    var body: some View {
        ScreenView { _ in
            H1(text: "We can't show results")
            Text(app.loadError.map { e in (e as? NTError)?.message ?? e.localizedDescription } ?? "")
                .nt(.body())
                .foregroundStyle(p.ink.color)
                .padding(.top, 16)
            Text(Copy.nothingScored).text(.lede).padding(.top, 12)
            Spacer(minLength: 0)
            Btn(title: "Dashboard", kind: .secondary) { app.go(.dashboard) }
                .padding(.top, 24)
        }
    }
}
