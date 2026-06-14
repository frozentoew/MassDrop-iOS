import SwiftUI

struct MainView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @StateObject private var unsubVM = UnsubscribeViewModel()
    @State private var showingConfirmation = false
    @Environment(\.horizontalSizeClass) private var hSizeClass

    private var isIPad: Bool { hSizeClass == .regular }
    private var contentMaxWidth: CGFloat { isIPad ? 560 : .infinity }
    private var horizontalPadding: CGFloat { isIPad ? 0 : 20 }
    private var headerFontSize: CGFloat { isIPad ? 56 : 42 }

    var body: some View {
        NavigationView {
            ZStack {
                background.ignoresSafeArea()

                if isIPad {
                    // iPad: centered single-column layout
                    VStack(spacing: 0) {
                        headerText
                            .padding(.top, 16)
                            .padding(.horizontal, 24)
                            .frame(maxWidth: contentMaxWidth)

                        Spacer()

                        Group {
                            if unsubVM.needsRelogin {
                                securityAlertView
                            } else if unsubVM.subscriptions.isEmpty && !unsubVM.isProcessing {
                                readyStateView
                            } else {
                                processingStateView
                            }
                        }
                        .frame(maxWidth: contentMaxWidth)
                        .padding(.horizontal, 0)

                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    // iPhone: original layout
                    VStack(spacing: 0) {
                        headerText
                            .padding(.top, 8)
                            .padding(.horizontal, 24)

                        Spacer()

                        Group {
                            if unsubVM.needsRelogin {
                                securityAlertView
                            } else if unsubVM.subscriptions.isEmpty && !unsubVM.isProcessing {
                                readyStateView
                            } else {
                                processingStateView
                            }
                        }
                        .padding(.horizontal, 20)

                        Spacer()
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { authVM.signOut() }) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.red)
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().strokeBorder(.white.opacity(0.40), lineWidth: 0.8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .alert("Confirm Unsubscribe", isPresented: $showingConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Unsubscribe All", role: .destructive) {
                    Task { await unsubVM.unsubscribeAll(authVM: authVM) }
                }
            } message: {
                Text("This will unsubscribe from \(unsubVM.selectedCount) channels. This cannot be undone.")
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - Background

    @ViewBuilder
    private var background: some View {
        if #available(iOS 18.0, *) {
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                    [0.0, 0.5], [0.5, 0.3], [1.0, 0.5],
                    [0.0, 1.0], [0.5, 1.0], [1.0, 1.0]
                ],
                colors: [
                    .white, Color(red: 1, green: 0.96, blue: 0.94), .white,
                    Color(red: 1, green: 0.94, blue: 0.92), Color(red: 1, green: 0.90, blue: 0.88), Color(red: 1, green: 0.96, blue: 0.94),
                    .white, Color(red: 1, green: 0.96, blue: 0.92), .white
                ]
            )
        } else {
            Color(red: 1, green: 0.97, blue: 0.96)
        }
    }

    // MARK: - Header

    private var headerText: some View {
        Text("MASS\nDROP")
            .font(.system(size: headerFontSize, weight: .black, design: .rounded))
            .foregroundStyle(
                LinearGradient(
                    colors: [.red, Color(red: 1, green: 0.45, blue: 0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Security alert

    private var securityAlertView: some View {
        glassCard {
            VStack(spacing: 24) {
                glassIcon("exclamationmark.shield.fill", color: .orange, size: 48)

                VStack(spacing: 8) {
                    Text("Security Alert")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("A security issue was detected.\nPlease sign in again.")
                        .font(.system(size: 15, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }

                glassButton(
                    label: "Sign In Again",
                    icon: "arrow.clockwise",
                    gradient: [.orange, Color(red: 1, green: 0.65, blue: 0.1)]
                ) { authVM.signOut() }
            }
        }
    }

    // MARK: - Ready state

    private var readyStateView: some View {
        let isLoading = unsubVM.statusMessage == "Loading subscriptions..."
        return glassCard {
            VStack(spacing: 24) {
                glassIcon("person.2.slash", color: .red, size: 48)

                VStack(spacing: 8) {
                    Text("Ready to Drop")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("Load your subscriptions to begin.")
                        .font(.system(size: 15, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                glassButton(
                    label: isLoading ? "Loading…" : "Load Subscriptions",
                    icon: isLoading ? nil : "arrow.down.circle.fill",
                    gradient: [.red, Color(red: 1, green: 0.45, blue: 0.1)],
                    isLoading: isLoading
                ) {
                    Task { await unsubVM.loadSubscriptions(authVM: authVM) }
                }
                .disabled(isLoading)

                if !unsubVM.statusMessage.isEmpty && !isLoading {
                    Text(unsubVM.statusMessage)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    // MARK: - Processing state

    @ViewBuilder
    private var processingStateView: some View {
        if unsubVM.isProcessing {
            progressView
        } else if unsubVM.isComplete {
            completedView
        } else if unsubVM.quotaExceeded {
            quotaView
        } else {
            subscriptionListView
        }
    }

    private var progressView: some View {
        glassCard {
            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.40), lineWidth: 8)
                        .frame(width: 100, height: 100)
                    Circle()
                        .trim(from: 0, to: unsubVM.progress)
                        .stroke(
                            LinearGradient(colors: [.red, .orange], startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .frame(width: 100, height: 100)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut, value: unsubVM.progress)
                    Text("\(Int(unsubVM.progress * 100))%")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                }

                Text(unsubVM.statusMessage)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var completedView: some View {
        let hasFailures = unsubVM.failedCount > 0
        return glassCard {
            VStack(spacing: 24) {
                glassIcon(
                    hasFailures ? "exclamationmark.circle.fill" : "checkmark.circle.fill",
                    color: hasFailures ? .orange : .green,
                    size: 52
                )

                Text(hasFailures ? "Partially Done" : "All Done!")
                    .font(.system(size: 26, weight: .black, design: .rounded))

                Text(unsubVM.statusMessage)
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(hasFailures ? .orange : .secondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13))
                    Text("Sign out before closing the app.")
                        .font(.system(size: 13, design: .rounded))
                }
                .foregroundStyle(.orange)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.orange.opacity(0.12), in: Capsule())

                glassButton(
                    label: "Sign Out",
                    icon: "rectangle.portrait.and.arrow.right",
                    gradient: [.red, Color(red: 1, green: 0.45, blue: 0.1)]
                ) { authVM.signOut() }
            }
        }
    }

    private var quotaView: some View {
        glassCard {
            VStack(spacing: 20) {
                glassIcon("clock.fill", color: .orange, size: 48)
                Text(unsubVM.statusMessage)
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var subscriptionListView: some View {
        VStack(spacing: 0) {
            // iPad padding is handled by the parent frame; iPhone uses .padding(.horizontal, 20)
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(unsubVM.statusMessage)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Text("Tap a channel to toggle it")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(unsubVM.selectedCount) of \(unsubVM.subscriptions.count)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.red)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial)

            Divider().opacity(0.3)

            HStack(spacing: 12) {
                Button("Select All") { unsubVM.selectAll() }
                    .disabled(unsubVM.selectedCount == unsubVM.subscriptions.count)
                Spacer()
                Button("Deselect All") { unsubVM.deselectAll() }
                    .disabled(unsubVM.selectedCount == 0)
            }
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .tint(.red)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)

            Divider().opacity(0.3)

            List(unsubVM.subscriptions) { sub in
                let isSelected = unsubVM.selectedIds.contains(sub.id)
                HStack(spacing: 12) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundStyle(isSelected ? .red.opacity(0.80) : .secondary.opacity(0.5))
                    Text(sub.title)
                        .font(.system(size: 15, design: .rounded))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
                .onTapGesture { unsubVM.toggleSelection(sub.id) }
                .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .modifier(ScrollBackgroundHidden())

            Divider().opacity(0.3)

            glassButton(
                label: "Unsubscribe All \(unsubVM.selectedCount)",
                icon: "play.fill",
                gradient: [.red, Color(red: 1, green: 0.45, blue: 0.1)]
            ) { showingConfirmation = true }
                .disabled(unsubVM.selectedCount == 0)
                .opacity(unsubVM.selectedCount == 0 ? 0.5 : 1)
                .padding(16)
                .background(.ultraThinMaterial)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.70), .white.opacity(0.10)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.08), radius: 24, y: 8)
    }

    // MARK: - Shared helpers

    @ViewBuilder
    private func glassCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(28)
            .frame(maxWidth: .infinity)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.50), .white.opacity(0.05), .clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.80), .white.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.2
                        )
                }
            }
            .shadow(color: .black.opacity(0.10), radius: 30, y: 10)
            .shadow(color: .white.opacity(0.50), radius: 1, x: 0, y: -1)
    }

    private func glassIcon(_ name: String, color: Color, size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: size * 1.9, height: size * 1.9)
                .overlay {
                    Circle()
                        .fill(LinearGradient(colors: [.white.opacity(0.55), .clear], startPoint: .top, endPoint: .center))
                }
                .overlay { Circle().strokeBorder(.white.opacity(0.55), lineWidth: 1) }
                .shadow(color: color.opacity(0.20), radius: 16, y: 6)
            Image(systemName: name)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(LinearGradient(colors: [color, color.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
    }

    @ViewBuilder
    private func glassButton(
        label: String,
        icon: String?,
        gradient: [Color],
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView().tint(.white)
                } else if let icon {
                    Image(systemName: icon).font(.system(size: 15, weight: .semibold))
                }
                Text(label).font(.system(size: 16, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background {
                ZStack {
                    Capsule().fill(LinearGradient(colors: gradient, startPoint: .leading, endPoint: .trailing))
                    Capsule().fill(LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .top, endPoint: .center))
                    Capsule().strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.65), .white.opacity(0.10)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1
                    )
                }
            }
            .shadow(color: gradient.first?.opacity(0.40) ?? .clear, radius: 14, y: 6)
            .shadow(color: .white.opacity(0.40), radius: 1, x: 0, y: -1)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Scroll background modifier

private struct ScrollBackgroundHidden: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.scrollContentBackground(.hidden)
        } else {
            content
        }
    }
}

#Preview {
    MainView().environmentObject(AuthViewModel())
}
