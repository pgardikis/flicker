import SwiftUI

/// The menu bar icon: a charging station, with a "!" while the battery is low and slashed while
/// warnings are muted, plus the percentage when it's shown. StatusItem draws the real one from
/// the same symbol and text; this view draws it for the screenshots.
struct MenuBarLabel: View {
    let isLow: Bool
    let isMuted: Bool
    let percent: Int?

    var body: some View {
        HStack {
            Image(systemName: Self.symbolName(isLow: isLow, isMuted: isMuted))
            if let percent {
                Text("\(percent)%")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityText(isLow: isLow, isMuted: isMuted, percent: percent))
    }

    static func symbolName(isLow: Bool, isMuted: Bool) -> String {
        isMuted ? "ev.charger.slash" : isLow ? "ev.charger.exclamationmark.fill" : "ev.charger"
    }

    /// The app's name and what the icon shows, such as "Flicker, 41%, low battery", since
    /// VoiceOver would otherwise read the symbol's name, "Electric Vehicle Charger".
    static func accessibilityText(isLow: Bool, isMuted: Bool, percent: Int?) -> String {
        var parts = ["Flicker"]
        if let percent { parts.append("\(percent)%") }
        if isLow { parts.append("low battery") }
        if isMuted { parts.append("warnings muted") }
        return parts.joined(separator: ", ")
    }
}
