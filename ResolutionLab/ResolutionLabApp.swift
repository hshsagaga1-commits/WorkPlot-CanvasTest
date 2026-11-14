import SwiftUI

@main
struct ResolutionLabApp: App {
    var body: some Scene {
        WindowGroup {
            Dashboard()
                .preferredColorScheme(.dark)
                .tint(Color(red: 0.41, green: 0.89, blue: 0.80))
        }
    }
}
