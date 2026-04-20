import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authVM: AuthViewModel

    var body: some View {
        ZStack {
            // ── Mesh gradient background ──────────────────────────────
            background.ignoresSafeArea()

            VStack {
                Spacer()
                glassCard
                Spacer()
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var background: some View {
        if #available(iOS 18.0, *) {
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                    [0.0, 0.5], [0.4, 0.4], [1.0, 0.5],
                    [0.0, 1.0], [0.5, 1.0], [1.0, 1.0]
                ],
                colors: [
                    Color(red: 1.0, green: 0.82, blue: 0.80),
                    Color(red: 1.0, green: 0.75, blue: 0.78),
                    Color(red: 1.0, green: 0.75, blue: 0.72),
                    Color(red: 1.0, green: 0.68, blue: 0.72),
                    Color(red: 1.0, green: 0.70, blue: 0.75),
                    Color(red: 1.0, green: 0.78, blue: 0.76),
                    Color(red: 1.0, green: 0.78, blue: 0.72),
                    Color(red: 1.0, green: 0.80, blue: 0.76),
                    Color(red: 1.0, green: 0.82, blue: 0.80)
                ]
            )
        } else {
            LinearGradient(
                colors: [Color(red: 1, green: 0.80, blue: 0.78), Color(red: 1, green: 0.90, blue: 0.76)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    // MARK: - Glass card

    private var glassCard: some View {
        VStack(spacing: 32) {
            iconView
            titleView
            actionView
            securityBadge
        }
        .padding(32)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(.ultraThinMaterial)
                // Specular top sheen
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.50), .white.opacity(0.05), .clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
                // Glass rim
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.80), .white.opacity(0.20), .white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
            }
        }
        .shadow(color: .black.opacity(0.20), radius: 40, y: 16)
        .shadow(color: .white.opacity(0.50), radius: 1, x: 0, y: -1)
    }

    // MARK: - Icon

    private var iconView: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 90, height: 90)
                .overlay {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.60), .clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                }
                .overlay {
                    Circle()
                        .strokeBorder(.white.opacity(0.60), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.12), radius: 6, y: 6)

            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.red, Color(red: 1, green: 0.45, blue: 0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }

    // MARK: - Title

    private var titleView: some View {
        VStack(spacing: 8) {
            Text("MASS DROP")
                .font(.system(size: 36, weight: .black, design: .rounded))
                .foregroundStyle(.primary)

            Text("Unsubscribe all channels in one tap.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Action

    private var actionView: some View {
        VStack(spacing: 14) {
            if authVM.isLoading {
                ProgressView()
                    .scaleEffect(1.4)
                    .tint(.red)
                    .frame(height: 54)
            } else {
                glassButton(
                    label: "Sign in with Google",
                    icon: "person.crop.circle.fill",
                    gradient: [.red, Color(red: 1, green: 0.50, blue: 0.15)]
                ) {
                    Task { await authVM.signIn() }
                }
            }

            if let error = authVM.error {
                Text(error)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Security badge

    private var securityBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 11))
            Text("Secured with PKCE & OAuth 2.0")
                .font(.system(size: 12, design: .rounded))
        }
        .foregroundStyle(.secondary)
    }

    // MARK: - Glass button

    private func glassButton(
        label: String,
        icon: String,
        gradient: [Color],
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                Text(label)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background {
                ZStack {
                    Capsule()
                        .fill(LinearGradient(colors: gradient, startPoint: .leading, endPoint: .trailing))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.35), .clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.65), .white.opacity(0.10)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            }
            .shadow(color: gradient.first?.opacity(0.45) ?? .clear, radius: 14, y: 6)
            .shadow(color: .white.opacity(0.40), radius: 1, x: 0, y: -1)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

#Preview("Normal") {
    LoginView().environmentObject(AuthViewModel())
}
#Preview("Loading") {
    let vm = AuthViewModel(); vm.isLoading = true
    return LoginView().environmentObject(vm)
}
#Preview("Error") {
    let vm = AuthViewModel(); vm.error = "Authentication failed"
    return LoginView().environmentObject(vm)
}
