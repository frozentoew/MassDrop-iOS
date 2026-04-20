import Foundation
import Combine

@MainActor
class UnsubscribeViewModel: ObservableObject {
    @Published var subscriptions: [Subscription] = []
    @Published var isProcessing = false
    @Published var progress: Double = 0.0
    @Published var statusMessage = ""
    @Published var isComplete = false
    @Published var quotaExceeded = false
    @Published var needsRelogin = false
    
    func loadSubscriptions(authVM: AuthViewModel) async {
        do {
            let appToken = try await authVM.getAppToken()

            statusMessage = "Loading subscriptions..."

            let response = try await APIManager.shared.fetchSubscriptions(
                appToken: appToken
            )
            
            subscriptions = response.subscriptions
            statusMessage = "Found \(response.totalCount) subscriptions"
            
        } catch APIError.quotaExceeded {
            statusMessage = "Quota exceeded. Try after 08:00 UTC."
            quotaExceeded = true
        } catch APIError.reloginRequired {
            statusMessage = "Security issue detected. Please login again."
            needsRelogin = true
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }
    
    func unsubscribeAll(authVM: AuthViewModel) async {
        isProcessing = true
        quotaExceeded = false
        needsRelogin = false
        progress = 0.0
        
        let total = Double(subscriptions.count)
        var completed = 0.0
        var failed = 0
        
        do {
            let appToken = try await authVM.getAppToken()

            for subscription in subscriptions {
                do {
                    try await APIManager.shared.unsubscribe(
                        subscriptionId: subscription.id,
                        appToken: appToken
                    )
                    
                    completed += 1
                    progress = completed / total
                    statusMessage = "Unsubscribed: \(Int(completed))/\(Int(total))"
                    
                    // Delay to respect rate limits
                    try await Task.sleep(nanoseconds: 150_000_000) // 0.15 seconds
                    
                } catch APIError.quotaExceeded {
                    quotaExceeded = true
                    statusMessage = "You have used up all credential tokens for the day. Try tomorrow again after 08:00 UTC to complete the remaining."
                    break
                } catch APIError.reloginRequired {
                    needsRelogin = true
                    statusMessage = "Security issue detected. Please login again."
                    break
                } catch {
                    failed += 1
                }
            }
            
            if !quotaExceeded && !needsRelogin {
                isComplete = true
                let message = failed > 0
                    ? "Completed with \(failed) failures"
                    : "Completed"
                statusMessage = message
            }
            
        } catch APIError.reloginRequired {
            needsRelogin = true
            statusMessage = "Security issue detected. Please login again."
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
        
        isProcessing = false
    }
}

