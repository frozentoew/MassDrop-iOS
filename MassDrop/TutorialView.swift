import SwiftUI

struct TutorialView: View {
    let onComplete: () -> Void
    @State private var currentPage = 0

    let pages = [
        TutorialPage(
            title: "Welcome",
            description: "Unsubscribe from all your YouTube channels in one tap.",
            imageName: "play.rectangle.fill",
            color: Color(red: 1, green: 0.25, blue: 0.20)
        ),
        TutorialPage(
            title: "Google Account Required",
            description: "MassDrop works only with YouTube accounts linked to a Google account. Apple ID or third-party logins won't work.",
            imageName: "person.badge.key.fill",
            color: Color(red: 0.25, green: 0.45, blue: 1.0)
        ),
        TutorialPage(
            title: "Quick & Easy",
            description: "Your subscriptions load automatically. Review them and tap one button to drop them all.",
            imageName: "bolt.fill",
            color: Color(red: 1, green: 0.55, blue: 0.10)
        ),
        TutorialPage(
            title: "Daily Limit",
            description: "YouTube allows up to 200 removals per day. If you have more, run again tomorrow after 08:00 UTC.",
            imageName: "exclamationmark.triangle.fill",
            color: Color(red: 1, green: 0.45, blue: 0.10)
        )
    ]

    var body: some View {
        ZStack {
            animatedBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Pages
                TabView(selection: $currentPage) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        pageCard(pages[index]).tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.40), value: currentPage)

                // Controls
                controlsArea
                    .padding(.bottom, 52)
                    .padding(.top, 12)
            }
        }
    }

    // MARK: - Animated background

    @ViewBuilder
    private var animatedBackground: some View {
        let c = pages[currentPage].color
        if #available(iOS 18.0, *) {
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                    [0.0, 0.5], [0.4, 0.4], [1.0, 0.5],
                    [0.0, 1.0], [0.5, 1.0], [1.0, 1.0]
                ],
                colors: [
                    c.opacity(0.50), c.opacity(0.30), c.opacity(0.40),
                    c.opacity(0.25), c.opacity(0.12), c.opacity(0.20),
                    c.opacity(0.10), c.opacity(0.08), c.opacity(0.22)
                ]
            )
            .animation(.easeInOut(duration: 0.50), value: currentPage)
        } else {
            LinearGradient(
                colors: [c.opacity(0.30), c.opacity(0.08)],
                startPoint: .top,
                endPoint: .bottom
            )
            .animation(.easeInOut(duration: 0.40), value: currentPage)
        }
    }

    // MARK: - Page card

    private func pageCard(_ page: TutorialPage) -> some View {
        VStack(spacing: 32) {
            Spacer()

            // Icon in glass circle
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 130, height: 130)
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
                    .overlay { Circle().strokeBorder(.white.opacity(0.65), lineWidth: 1.2) }
                    .shadow(color: page.color.opacity(0.28), radius: 24, y: 10)

                Image(systemName: page.imageName)
                    .font(.system(size: 60, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [page.color, page.color.opacity(0.60)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            // Text in glass card
            VStack(spacing: 12) {
                Text(page.title)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                Text(page.description)
                    .font(.system(size: 16, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 8)
            }
            .padding(28)
            .frame(maxWidth: .infinity)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.55), .clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.75), .white.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.2
                        )
                }
            }
            .shadow(color: .black.opacity(0.08), radius: 24, y: 8)
            .padding(.horizontal, 4)

            Spacer()
        }
        .padding(.horizontal, 28)
    }

    // MARK: - Controls

    private var controlsArea: some View {
        VStack(spacing: 20) {
            // Dot indicators
            HStack(spacing: 8) {
                ForEach(0..<pages.count, id: \.self) { i in
                    Capsule()
                        .fill(i == currentPage ? pages[currentPage].color : .secondary.opacity(0.30))
                        .frame(width: i == currentPage ? 28 : 8, height: 8)
                        .animation(.spring(response: 0.35), value: currentPage)
                }
            }

            // Button
            if currentPage == pages.count - 1 {
                actionButton(
                    label: "Get Started",
                    color: pages[currentPage].color,
                    action: onComplete
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else {
                actionButton(
                    label: "Next",
                    color: pages[currentPage].color,
                    action: { withAnimation { currentPage += 1 } }
                )
            }
        }
        .padding(.horizontal, 40)
        .animation(.easeInOut(duration: 0.25), value: currentPage)
    }

    private func actionButton(label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background {
                    ZStack {
                        Capsule()
                            .fill(LinearGradient(
                                colors: [color, color.opacity(0.70)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                        Capsule()
                            .fill(LinearGradient(
                                colors: [.white.opacity(0.35), .clear],
                                startPoint: .top,
                                endPoint: .center
                            ))
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
                .shadow(color: color.opacity(0.40), radius: 14, y: 6)
                .shadow(color: .white.opacity(0.40), radius: 1, x: 0, y: -1)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Model

struct TutorialPage {
    let title: String
    let description: String
    let imageName: String
    let color: Color
}

#Preview {
    TutorialView(onComplete: {})
}
