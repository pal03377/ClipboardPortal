import SwiftUI


extension View {
    // KeyPress listener that only works from MacOS 14 upwards (because the API only works with 14+)
    func keyPressMacOS14(_ key: KeyEquivalent, action: @escaping () -> Bool) -> some View {
        if #available(macOS 14, *) {
            return self.onKeyPress(key) {
                if action() { return .handled }
                return .ignored
            }
        } else {
            return self
        }
    }
}
