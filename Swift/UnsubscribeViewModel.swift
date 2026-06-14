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

            // Use the batch endpoint: the per-channel delete endpoint is capped at
            // 30 requests/min, so deleting >30 channels in a loop gets rate-limited
            // partway through. The batch endpoint performs every delete inside a
            // single streamed request server-side, bypassing the per-request limit,
            // and reports progress per channel so the bar updates live.
            let result = try await APIManager.shared.batchUnsubscribe(
                subscriptionIds: targets.map { $0.id },
                appToken: appToken
            ) { [weak self] completed, total in
                guard let self, total > 0 else { return }
                self.progress = Double(completed) / Double(total)
                self.statusMessage = "Unsubscribing \(completed) of \(total)…"
            }

            progress = 1.0

            // A whole-run quota/auth failure isn't an HTTP error — the stream
            // completes normally and surfaces the cause in the result `failures`.
            let quotaHit = result.failures.contains { $0.reason.localizedCaseInsensitiveContains("quota") }
            let authHit = result.failures.contains { $0.reason.localizedCaseInsensitiveContains("authentication") }

            if result.succeeded == 0 && quotaHit {
                quotaExceeded = true
                statusMessage = "Daily quota exceeded. Try after 08:00 UTC."
                isProcessing = false
                return
            }
            if result.succeeded == 0 && authHit {
                needsRelogin = true
                statusMessage = "Security issue detected. Please login again."
                isProcessing = false
                return
            }

            failedCount = result.failed
            isComplete = true
            if result.failed == 0 {
                statusMessage = "All \(result.succeeded) channels unsubscribed"
            } else {
                // Partial run: tell the user *why* the rest failed so a quota cutoff
                // isn't mistaken for an app bug.
                let reason: String
                if quotaHit {
                    reason = "daily quota reached — try again after 08:00 UTC"
                } else if authHit {
                    reason = "session expired — sign in again"
                } else {
                    reason = result.failures.first?.reason ?? "some channels couldn't be removed"
                }
                statusMessage = "\(result.succeeded) unsubscribed, \(result.failed) failed — \(reason)"
            }

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

