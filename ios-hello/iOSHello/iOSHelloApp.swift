import SwiftUI

@main
struct iOSHelloApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Hello, iPhone!")
                .font(.system(size: 48, weight: .bold))
                .multilineTextAlignment(.center)
                .padding()
        }
    }
}
