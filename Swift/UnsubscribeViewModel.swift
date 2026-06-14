import Foundation
import Combine

@MainActor
class UnsubscribeViewModel: ObservableObject {
    @Published var subscriptions: [Subscription] = []
    @Published var selectedIds: Set<String> = []
    @Published var isProcessing = false
    @Published var progress: Double = 0.0
    @Published var statusMessage = ""
    @Published var isComplete = false
    @Published var quotaExceeded = false
    @Published var needsRelogin = false
    @Published var failedCount = 0

    var selectedCount: Int { selectedIds.count }

    func toggleSelection(_ id: String) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }

    func selectAll() {
        selectedIds = Set(subscriptions.map { $0.id })
    }

    func deselectAll() {
        selectedIds.removeAll()
    }

    func loadSubscriptions(authVM: AuthViewModel) async {
        do {
            let appToken = try await authVM.getAppToken()

            statusMessage = "Loading subscriptions..."

            let response = try await APIManager.shared.fetchSubscriptions(
                appToken: appToken
            )

            subscriptions = response.subscriptions
            selectedIds = Set(response.subscriptions.map { $0.id })
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
        failedCount = 0
        progress = 0.0

        let targets = subscriptions.filter { selectedIds.contains($0.id) }
        statusMessage = "Unsubscribing \(targets.count) channels…"

        do {
            let appToken = try await authVM.getAppToken()

            let result = try await APIManager.shared.batchUnsubscribe(
                subscriptionIds: targets.map { $0.id },
                appToken: appToken
            )

            failedCount = result.failed
            progress = 1.0
            isComplete = true
            statusMessage = result.failed > 0
                ? "\(result.succeeded) unsubscribed, \(result.failed) failed"
                : "All \(result.succeeded) channels unsubscribed"

        } catch APIError.quotaExceeded {
            quotaExceeded = true
            statusMessage = "Daily quota exceeded. Try after 08:00 UTC."
        } catch APIError.reloginRequired {
            needsRelogin = true
            statusMessage = "Security issue detected. Please login again."
        } catch APIError.rateLimited {
            statusMessage = "Rate limited. Please wait a minute and try again."
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }

        isProcessing = false
    }
}

