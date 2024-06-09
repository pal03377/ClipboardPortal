import SwiftUI


extension View {
    // focusEffectDisabled Modifier that only works from MacOS 14 upwards (because the API only works with 14+)
    func focusEffectDisabledMacOS14() -> some View {
        if #available(macOS 14, *) {
            return self.focusEffectDisabled()
        } else {
            return self
        }
    }
}

