// THEME.SWIFT HOLDS THE APP'S COLORS, ACCENT CHOICES, TEXT SIZES AND FONTS
// IT ALSO PASSES THE COLORS AND TEXT SIZES DOWN TO EVERY SCREEN

import CoreText
import SwiftUI
import UIKit


// THE COLORS

// One color, stored as red, green, blue and opacity values from 0 to 1
struct RGB: Equatable {

    // The red, green, blue and opacity values
    var r: Double
    var g: Double
    var b: Double
    var a: Double = 1

    // Make a color from the four values, fully solid unless an opacity is given
    init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    // Make a color from a hex number like 0x0066cc, with an optional opacity
    init(_ hex: UInt32, alpha: Double = 1) {
        r = Double((hex >> 16) & 0xff) / 255
        g = Double((hex >> 8) & 0xff) / 255
        b = Double(hex & 0xff) / 255
        a = alpha
    }

    // Blend this color with another, using share parts of this one and the rest of the other
    func mix(_ other: RGB, _ share: Double) -> RGB {
        RGB(r: r * share + other.r * (1 - share), g: g * share + other.g * (1 - share), b: b * share + other.b * (1 - share), a: a * share + other.a * (1 - share))
    }

    // The same color with a new opacity
    func alpha(_ value: Double) -> RGB { RGB(r: r, g: g, b: b, a: value) }

    // The color as a SwiftUI Color and as a UIKit UIColor
    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
    var ui: UIColor { UIColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a)) }
}


// The accent colors people can pick, and the app's standard animation curve
enum Theme {

    // One accent color, with its light mode color, dark mode color and dark mode fill color
    struct Accent {
        var light: UInt32
        var dark: UInt32
        var fillDark: UInt32
    }

    // Every accent color, by name
    static let accents: [String: Accent] = [
        "blue": Accent(light: 0x0066cc, dark: 0x2997ff, fillDark: 0x0071e3),
        "indigo": Accent(light: 0x4f46e5, dark: 0x8e8cff, fillDark: 0x5b54e8),
        "violet": Accent(light: 0x7c3aed, dark: 0xbf8bff, fillDark: 0x8b4ff0),
        "teal": Accent(light: 0x00747a, dark: 0x40c8d4, fillDark: 0x00808a),
        "amber": Accent(light: 0xa65200, dark: 0xffa94d, fillDark: 0xb35900),
        "rose": Accent(light: 0xc2185b, dark: 0xff7eb0, fillDark: 0xc7206a),
        "graphite": Accent(light: 0x4a4a4f, dark: 0xb8b8be, fillDark: 0x5a5a60),
    ]

    // The animation that starts fast and slows down at the end, over 0.36 seconds or over ms milliseconds
    static let ease = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.36)
    static func ease(_ ms: Double) -> Animation { .timingCurve(0.22, 1, 0.36, 1, duration: ms / 1000) }
}


// The full set of colors the screens use
struct Palette: Equatable {

    // Whether this is the dark set of colors
    var dark: Bool

    // The background, the card color, the main text color and the softer text color
    var bg: RGB
    var surface: RGB
    var ink: RGB
    var ink2: RGB

    // The thin lines, the gray fill and the gray guide spiral
    var line: RGB
    var fill: RGB
    var guide: RGB

    // The accent color, its fill for buttons, and its pale version
    var accent: RGB
    var accentFill: RGB
    var accentSoft: RGB

    // The color of the sliding knob in segmented controls
    var segThumb: RGB

    // How thick the thin lines are, in points
    var hair: CGFloat

    // The name of the accent color in use
    var accentId: String

    // Build the colors for light or dark mode, an accent name, and the More Contrast setting
    static func make(dark: Bool, accent: String, moreContrast: Bool) -> Palette {

        // Look up the accent, or use blue if the name isn't found
        let a = Theme.accents[accent] ?? Theme.accents["blue"]!
        var p: Palette

        // Pick the dark colors or the light colors
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

        // With More Contrast on, make the lines darker gray and twice as thick
        if moreContrast {
            p.line = RGB(0x8a8a8a)
            p.hair = 2
        }
        return p
    }

    // The color shown in the accent picker for an accent name, or blue if the name isn't found
    func swatch(_ id: String) -> RGB {
        let a = Theme.accents[id] ?? Theme.accents["blue"]!
        return RGB(dark ? a.fillDark : a.light)
    }
}


extension Palette {

    // The colors the drawing pad uses, starting as the light blue set
    @MainActor static var current = Palette.make(dark: false, accent: "blue", moreContrast: false)
}


// The message the app sends out to the NotificationCenter list when the colors change
extension Notification.Name {
    static let paletteChanged = Notification.Name("neurotrace.paletteChanged")
}


// The key that stores the colors for the screens, starting as the light blue set
private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette.make(dark: false, accent: "blue", moreContrast: false)
}


// THE TEXT SIZES

// The text size setting and the size of the screen
struct Typography {

    // How much to grow or shrink text, and the normal body text size
    var scale: CGFloat = 1
    var body: CGFloat = 17

    // The width and height of the screen, in points
    var width: CGFloat = 390
    var height: CGFloat = 844

    // Whether this is an iPad
    var pad = false

    // True on an iPad at least 700 points wide, where the tabs go along the top
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


// The key that stores the text sizes for the screens
private struct TypographyKey: EnvironmentKey {
    static let defaultValue = Typography()
}


// Lets every screen read and set the colors and text sizes
extension EnvironmentValues {

    // The colors
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }

    // The text sizes
    var typo: Typography {
        get { self[TypographyKey.self] }
        set { self[TypographyKey.self] = newValue }
    }
}


// THE FONTS

// One text style, saying which font, what size, how bold and how much space between lines
struct NTFont: Equatable {

    // Whether to use the display font or the fixed width font, instead of the body font
    var display = false
    var mono = false

    // The size in points, or nil for the normal body size
    var size: CGFloat? = nil

    // How bold the text is, from 100 to 900
    var weight: CGFloat = 400

    // The space each line takes, as a multiple of the text size
    var lineHeight: CGFloat = 1.5

    // A text style in the body font
    static func body(_ size: CGFloat? = nil, _ weight: CGFloat = 400, lineHeight: CGFloat = 1.5) -> NTFont {
        NTFont(size: size, weight: weight, lineHeight: lineHeight)
    }

    // A text style in the display font, for headlines
    static func display(_ size: CGFloat, _ weight: CGFloat = 600, lineHeight: CGFloat = 1.2) -> NTFont {
        NTFont(display: true, size: size, weight: weight, lineHeight: lineHeight)
    }

    // A text style in the fixed width font
    static func mono(_ size: CGFloat? = nil, _ weight: CGFloat = 400, lineHeight: CGFloat = 1.5) -> NTFont {
        NTFont(mono: true, size: size, weight: weight, lineHeight: lineHeight)
    }
}


// Loads the app's font files and makes fonts from them
enum Fonts {

    // The names of the body font and the display font
    static let atkinson = "AtkinsonHyperlegibleNext-Regular"
    static let newsreader = "Newsreader16pt-Regular"

    // Fonts already made, by their style and size
    private static var cache: [String: UIFont] = [:]

    // Load the two font files that come with the app
    static func register() {
        for name in ["AtkinsonHyperlegibleNext", "Newsreader"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }

    // Make the font for a text style at a size, or give back the one made before
    static func make(_ font: NTFont, size: CGFloat) -> UIFont {

        // Give back the saved font if this style and size was made before
        let key = "\(font.display)|\(font.mono)|\(size)|\(font.weight)"
        if let hit = cache[key] { return hit }
        let made: UIFont

        // The fixed width system font, semibold at weight 600 and above
        if font.mono {
            made = UIFont.monospacedSystemFont(ofSize: size, weight: font.weight >= 600 ? .semibold : .regular)
        } else {

            // Set the weight, and for the display font also set the optical size between 6 and 72
            var axes: [NSNumber: CGFloat] = [NSNumber(value: 0x7767_6874): font.weight]
            if font.display { axes[NSNumber(value: 0x6f70_737a)] = min(72, max(6, size)) }

            // Make the display font or the body font with those settings
            let descriptor = UIFontDescriptor(fontAttributes: [
                .name: font.display ? newsreader : atkinson,
                UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): axes,
            ])
            made = UIFont(descriptor: descriptor, size: size)
        }

        // Save the font and give it back
        cache[key] = made
        return made
    }
}


// Puts a text style on a view at the reader's text size
private struct NTFontModifier: ViewModifier {

    // The text sizes and the text style to use
    @Environment(\.typo) private var typo
    var font: NTFont

    func body(content: Content) -> some View {

        // Work out the size and make the font
        let size = typo.scaled(font.size ?? typo.body)
        let ui = Fonts.make(font, size: size)

        // Set the font, the space between lines, and the space between letters
        content
            .font(Font(ui as CTFont))
            .lineSpacing(max(0, size * font.lineHeight - ui.lineHeight))
            .tracking(font.display ? -0.01 * size : (font.mono ? 0.06 * size : 0))
    }
}


extension View {

    // Put a text style on this view, like `.nt(.body())`
    func nt(_ font: NTFont) -> some View { modifier(NTFontModifier(font: font)) }
}
