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
        let total = targets.count
        statusMessage = "Unsubscribing \(total) channels…"

        do {
            let appToken = try await authVM.getAppToken()

            var succeeded = 0
            var failed = 0

            for (index, sub) in targets.enumerated() {
                do {
                    try await APIManager.shared.unsubscribe(
                        subscriptionId: sub.id,
                        appToken: appToken
                    )
                    succeeded += 1
                } catch APIError.quotaExceeded {
                    quotaExceeded = true
                    statusMessage = "Daily quota exceeded. Try after 08:00 UTC."
                    isProcessing = false
                    return
                } catch APIError.reloginRequired {
                    needsRelogin = true
                    statusMessage = "Security issue detected. Please login again."
                    isProcessing = false
                    return
                } catch {
                    failed += 1
                }

                progress = Double(index + 1) / Double(total)

                if index < total - 1 {
                    try? await Task.sleep(nanoseconds: 150_000_000) // 0.15s delay
                }
            }

            failedCount = failed
            isComplete = true
            statusMessage = failed > 0
                ? "\(succeeded) unsubscribed, \(failed) failed"
                : "All \(succeeded) channels unsubscribed"

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

