import CoreText
import SwiftUI
import UIKit

struct RGB: Equatable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double = 1

    init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    init(_ hex: UInt32, alpha: Double = 1) {
        r = Double((hex >> 16) & 0xff) / 255
        g = Double((hex >> 8) & 0xff) / 255
        b = Double(hex & 0xff) / 255
        a = alpha
    }

    func mix(_ other: RGB, _ share: Double) -> RGB {
        RGB(r: r * share + other.r * (1 - share), g: g * share + other.g * (1 - share), b: b * share + other.b * (1 - share), a: a * share + other.a * (1 - share))
    }

    func alpha(_ value: Double) -> RGB { RGB(r: r, g: g, b: b, a: value) }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
    var ui: UIColor { UIColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a)) }
}

enum Theme {
    struct Accent {
        var light: UInt32
        var dark: UInt32
        var fillDark: UInt32
    }

    static let accents: [String: Accent] = [
        "blue": Accent(light: 0x0066cc, dark: 0x2997ff, fillDark: 0x0071e3),
        "indigo": Accent(light: 0x4f46e5, dark: 0x8e8cff, fillDark: 0x5b54e8),
        "violet": Accent(light: 0x7c3aed, dark: 0xbf8bff, fillDark: 0x8b4ff0),
        "teal": Accent(light: 0x00747a, dark: 0x40c8d4, fillDark: 0x00808a),
        "amber": Accent(light: 0xa65200, dark: 0xffa94d, fillDark: 0xb35900),
        "rose": Accent(light: 0xc2185b, dark: 0xff7eb0, fillDark: 0xc7206a),
        "graphite": Accent(light: 0x4a4a4f, dark: 0xb8b8be, fillDark: 0x5a5a60),
    ]

    static let ease = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.36)
    static func ease(_ ms: Double) -> Animation { .timingCurve(0.22, 1, 0.36, 1, duration: ms / 1000) }
}

struct Palette: Equatable {
    var dark: Bool
    var bg: RGB
    var surface: RGB
    var ink: RGB
    var ink2: RGB
    var line: RGB
    var fill: RGB
    var guide: RGB
    var accent: RGB
    var accentFill: RGB
    var accentSoft: RGB
    var segThumb: RGB
    var hair: CGFloat
    var accentId: String

    static func make(dark: Bool, accent: String, moreContrast: Bool) -> Palette {
        let a = Theme.accents[accent] ?? Theme.accents["blue"]!
        var p: Palette
        if dark {
            p = Palette(
                dark: true, bg: RGB(0x000000), surface: RGB(0x1c1c1e), ink: RGB(0xf5f5f7), ink2: RGB(0xaeaeb2),
                line: RGB(0xffffff, alpha: 0.1), fill: RGB(0x3a3a3c), guide: RGB(0x48484a),
                accent: RGB(a.dark), accentFill: RGB(a.fillDark), accentSoft: RGB(a.fillDark).mix(RGB(0x000000), 0.32),
                segThumb: RGB(0x636366), hair: 1, accentId: accent
            )
        } else {
            p = Palette(
                dark: false, bg: RGB(0xf5f5f7), surface: RGB(0xffffff), ink: RGB(0x1d1d1f), ink2: RGB(0x6e6e73),
                line: RGB(0x000000, alpha: 0.08), fill: RGB(0xe8e8ed), guide: RGB(0xd2d2d7),
                accent: RGB(a.light), accentFill: RGB(a.light), accentSoft: RGB(a.light).mix(RGB(0xffffff), 0.10),
                segThumb: RGB(0xffffff), hair: 1, accentId: accent
            )
        }
        if moreContrast {
            p.line = RGB(0x8a8a8a)
            p.hair = 2
        }
        return p
    }

    func swatch(_ id: String) -> RGB {
        let a = Theme.accents[id] ?? Theme.accents["blue"]!
        return RGB(dark ? a.fillDark : a.light)
    }
}

extension Palette {
    // The colors the pad draws with. UIKit drawing code can't read SwiftUI's environment, so RootView
    // keeps this matched to the current theme
    @MainActor static var current = Palette.make(dark: false, accent: "blue", moreContrast: false)
}

// The message the app sends out to the NotificationCenter list when the colors change
extension Notification.Name {
    static let paletteChanged = Notification.Name("neurotrace.paletteChanged")
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette.make(dark: false, accent: "blue", moreContrast: false)
}

struct Typography {
    var scale: CGFloat = 1
    var body: CGFloat = 17
    var width: CGFloat = 390
    var height: CGFloat = 844
    // Whether this is an iPad, read once by the root view
    var pad = false

    // iPads put the tabs along the top, like Apple's own iPad apps. Phones and narrow windows keep them at the bottom
    var tabsOnTop: Bool { pad && width >= 700 }

    // A point size grown or shrunk to match the reader's text size setting
    func scaled(_ size: CGFloat) -> CGFloat { size * scale }

    // Apple's Body text size at each Dynamic Type setting, divided by the default 17
    static func scale(for size: DynamicTypeSize) -> CGFloat {
        switch size {
        case .xSmall: return 14 / 17
        case .small: return 15 / 17
        case .medium: return 16 / 17
        case .large: return 1
        case .xLarge: return 19 / 17
        case .xxLarge: return 21 / 17
        case .xxxLarge: return 23 / 17
        case .accessibility1: return 28 / 17
        case .accessibility2: return 33 / 17
        case .accessibility3: return 40 / 17
        case .accessibility4: return 47 / 17
        case .accessibility5: return 53 / 17
        @unknown default: return 1
        }
    }
}

private struct TypographyKey: EnvironmentKey {
    static let defaultValue = Typography()
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }

    var typo: Typography {
        get { self[TypographyKey.self] }
        set { self[TypographyKey.self] = newValue }
    }
}

struct NTFont: Equatable {
    var display = false
    var mono = false
    var size: CGFloat? = nil
    var weight: CGFloat = 400
    var lineHeight: CGFloat = 1.5

    static func body(_ size: CGFloat? = nil, _ weight: CGFloat = 400, lineHeight: CGFloat = 1.5) -> NTFont {
        NTFont(size: size, weight: weight, lineHeight: lineHeight)
    }

    static func display(_ size: CGFloat, _ weight: CGFloat = 600, lineHeight: CGFloat = 1.2) -> NTFont {
        NTFont(display: true, size: size, weight: weight, lineHeight: lineHeight)
    }

    static func mono(_ size: CGFloat? = nil, _ weight: CGFloat = 400, lineHeight: CGFloat = 1.5) -> NTFont {
        NTFont(mono: true, size: size, weight: weight, lineHeight: lineHeight)
    }
}

enum Fonts {
    static let atkinson = "AtkinsonHyperlegibleNext-Regular"
    static let newsreader = "Newsreader16pt-Regular"
    private static var cache: [String: UIFont] = [:]

    static func register() {
        for name in ["AtkinsonHyperlegibleNext", "Newsreader"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }

    static func make(_ font: NTFont, size: CGFloat) -> UIFont {
        let key = "\(font.display)|\(font.mono)|\(size)|\(font.weight)"
        if let hit = cache[key] { return hit }
        let made: UIFont
        if font.mono {
            made = UIFont.monospacedSystemFont(ofSize: size, weight: font.weight >= 600 ? .semibold : .regular)
        } else {
            var axes: [NSNumber: CGFloat] = [NSNumber(value: 0x7767_6874): font.weight]
            if font.display { axes[NSNumber(value: 0x6f70_737a)] = min(72, max(6, size)) }
            let descriptor = UIFontDescriptor(fontAttributes: [
                .name: font.display ? newsreader : atkinson,
                UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): axes,
            ])
            made = UIFont(descriptor: descriptor, size: size)
        }
        cache[key] = made
        return made
    }
}

private struct NTFontModifier: ViewModifier {
    @Environment(\.typo) private var typo
    var font: NTFont

    func body(content: Content) -> some View {
        let size = typo.scaled(font.size ?? typo.body)
        let ui = Fonts.make(font, size: size)
        content
            .font(Font(ui as CTFont))
            .lineSpacing(max(0, size * font.lineHeight - ui.lineHeight))
            .tracking(font.display ? -0.01 * size : (font.mono ? 0.06 * size : 0))
    }
}

extension View {
    func nt(_ font: NTFont) -> some View { modifier(NTFontModifier(font: font)) }
}
