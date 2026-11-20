import SwiftUI

@main
struct ObserverApp: App {
    var body: some Scene {
        WindowGroup {
            ObserverView()
                .preferredColorScheme(.dark)
                .tint(Color(red: 0.40, green: 0.87, blue: 0.78))
        }
    }
}
