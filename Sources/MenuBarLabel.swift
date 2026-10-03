import SwiftUI

/// The menu bar icon: a charging station, with a "!" while the battery is low and slashed while
/// warnings are muted, plus the percentage when it's shown.
struct MenuBarLabel: View {
    let isLow: Bool
    let isMuted: Bool
    let percent: Int?

    var body: some View {
        HStack {
            Image(systemName: isMuted ? "ev.charger.slash" : isLow ? "ev.charger.exclamationmark.fill" : "ev.charger")
            if let percent {
                Text("\(percent)%")
            }
        }
    }
}
