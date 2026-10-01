import SwiftUI

@MainActor
@Observable
final class HomeModel {
    unowned let app: AppModel

    init(app: AppModel) { self.app = app }

    func login() {
    }
}

struct HomeScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p
    @Environment(\.typo) private var typo

    var body: some View {
        let home = app.home
        ScreenView { _ in

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

            LockNote().padding(.top, 24)
            Text(Copy.credit).text(.sub).multilineTextAlignment(.center).fullWidth(.center).padding(.top, 20)
        }
    }
}
