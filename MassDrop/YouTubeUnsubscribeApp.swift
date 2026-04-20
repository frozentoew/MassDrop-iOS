import SwiftUI
import GoogleSignIn

@main
struct YouTubeUnsubscribeApp: App {
    @StateObject private var authVM = AuthViewModel()
    @AppStorage("tutorialCompleted") private var tutorialCompleted = false
    
    var body: some Scene {
        WindowGroup {
            Group {
                if !tutorialCompleted {
                    TutorialView(onComplete: {
                        tutorialCompleted = true
                    })
                } else if authVM.isAuthenticated {
                    MainView()
                        .environmentObject(authVM)
                } else {
                    LoginView()
                        .environmentObject(authVM)
                }
            }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
                guard let url = userActivity.webpageURL else { return }
                authVM.handleUniversalLink(url: url)
            }
            .onOpenURL { url in
                GIDSignIn.sharedInstance.handle(url)
            }
        }
    }
}
