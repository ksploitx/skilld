// ContentView.swift
// skilld — menubar app
//
// Popover UI: search bar, loading/offline states, skill list with
// install/remove/update actions, source repo link, per-row progress and errors.

import SwiftUI

// MARK: - Root view

struct ContentView: View {
    @State private var store = SkillStore()

    var body: some View {
        VStack(spacing: 0) {
            HeaderView()
            SearchBarView(store: store)
            Divider().opacity(0.3)
            BodyView(store: store)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .frame(width: 380, height: 500)
        .onAppear {
            store.refresh()
        }
    }
}

// MARK: - Header

private struct HeaderView: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "brain.filled.head.profile")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.purple, .indigo],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text("skilld")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.purple, .indigo],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            Text("library")
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [
                    Color(NSColor.windowBackgroundColor),
                    Color.purple.opacity(0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

// MARK: - Search bar

private struct SearchBarView: View {
    let store: SkillStore

    var body: some View {
        HStack(spacing: 8) {
            if store.isLoading {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 14, height: 14)
            } else {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Color.secondary.opacity(0.6))
                    .font(.system(size: 13))
            }
            TextField("Search skills…", text: Binding(
                get: { store.searchText },
                set: { store.searchText = $0; store.onSearchTextChanged($0) }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 13))

            if !store.searchText.isEmpty {
                Button {
                    store.searchText = ""
                    store.onSearchTextChanged("")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Color.secondary.opacity(0.6))
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Body (offline banner + list)

private struct BodyView: View {
    let store: SkillStore

    var body: some View {
        VStack(spacing: 0) {
            if store.isOffline {
                OfflineBannerView()
            }

            let displayed = store.isOffline ? store.filteredSkills : store.skills

            if store.isLoading && displayed.isEmpty {
                VStack {
                    Spacer()
                    ProgressView("Loading skills…")
                        .controlSize(.regular)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if displayed.isEmpty {
                ContentUnavailableView(
                    "No skills found",
                    systemImage: "magnifyingglass",
                    description: Text("Try a different search term.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(displayed) { skill in
                            SkillRowView(skill: skill, store: store)
                            if skill.id != displayed.last?.id {
                                Divider()
                                    .padding(.horizontal, 16)
                                    .opacity(0.4)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollContentBackground(.hidden)
            }
        }
    }
}

// MARK: - Offline banner

private struct OfflineBannerView: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 11))
                .foregroundColor(.orange)
            Text("Offline — showing bundled skills")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.orange)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.1))
    }
}

// MARK: - Skill row

private struct SkillRowView: View {
    let skill: SkillSummary
    let store: SkillStore

    @State private var isHovered = false

    private var installed: Bool { store.isInstalled(skill) }
    private var hasUpdate: Bool { store.hasUpdate(skill) }
    private var opState: SkillStore.SkillOpState? { store.operationState[skill.folderName] }
    private var isWorking: Bool { opState != nil }
    private var errorMsg: String? { store.operationError[skill.folderName] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {

                // Installed indicator dot
                Circle()
                    .fill(installed ? Color.green : Color.clear)
                    .stroke(installed ? Color.green : Color.secondary.opacity(0.3), lineWidth: 1.2)
                    .frame(width: 8, height: 8)
                    .padding(.top, 5)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(skill.name)
                            .font(.system(size: 13, weight: .semibold))
                        if hasUpdate {
                            UpdateBadge()
                        }
                    }

                    if let desc = skill.description {
                        Text(desc)
                            .font(.system(size: 11.5))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }

                    // Tags
                    if !skill.tags.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(skill.tags.prefix(4), id: \.self) { tag in
                                Text(tag)
                                    .font(.system(size: 9, weight: .medium))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.12))
                                    .foregroundColor(.accentColor)
                                    .clipShape(Capsule())
                            }
                        }
                    }

                    // Source repo link
                    if !skill.repo.isEmpty, let url = URL(string: skill.sourceURL) {
                        Link(destination: url) {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 9))
                                Text(skill.repo)
                                    .font(.system(size: 10))
                            }
                            .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()

                // Action area
                if isWorking {
                    VStack {
                        ProgressView()
                            .scaleEffect(0.65)
                            .frame(width: 24, height: 24)
                        Text(operationLabel(opState))
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                } else {
                    HStack(spacing: 6) {
                        if installed {
                            if hasUpdate {
                                PillButton(label: "Update", icon: "arrow.down.circle", style: .update) {
                                    store.update(skill)
                                }
                            }
                            PillButton(label: "Remove", icon: "trash", style: .destructive) {
                                store.remove(skill)
                            }
                        } else {
                            PillButton(label: "Install", icon: "arrow.down.to.line", style: .primary) {
                                store.install(skill)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // Per-row error
            if let msg = errorMsg {
                ErrorRowView(message: msg) {
                    store.clearError(for: skill)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.secondary.opacity(0.07) : Color.clear)
        )
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .animation(.easeInOut(duration: 0.2), value: installed)
    }

    private func operationLabel(_ state: SkillStore.SkillOpState?) -> String {
        switch state {
        case .installing: return "Installing…"
        case .removing:   return "Removing…"
        case .updating:   return "Updating…"
        case nil:         return ""
        }
    }
}

// MARK: - Update badge

private struct UpdateBadge: View {
    var body: some View {
        Text("Update")
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.orange, .pink],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
            .foregroundColor(.white)
    }
}

// MARK: - Pill button

private struct PillButton: View {
    enum Style { case primary, destructive, update }

    let label: String
    let icon: String
    let style: Style
    let action: () -> Void

    @State private var isHovered = false

    private var foreground: Color {
        switch style {
        case .primary:     return .white
        case .destructive: return isHovered ? .white : Color.red.opacity(0.8)
        case .update:      return .white
        }
    }

    private var gradient: LinearGradient {
        switch style {
        case .primary:
            return LinearGradient(colors: [.purple, .indigo], startPoint: .leading, endPoint: .trailing)
        case .destructive:
            return LinearGradient(
                colors: isHovered
                    ? [Color.red.opacity(0.9), Color.red.opacity(0.7)]
                    : [Color.red.opacity(0.12), Color.red.opacity(0.12)],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .update:
            return LinearGradient(colors: [.orange, .pink], startPoint: .leading, endPoint: .trailing)
        }
    }

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(foreground)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(gradient)
                        .opacity(isHovered && style != .destructive ? 0.85 : 1)
                )
                .scaleEffect(isHovered ? 0.97 : 1)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.spring(duration: 0.15), value: isHovered)
    }
}

// MARK: - Per-row error view

private struct ErrorRowView: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 10))
            Text(message)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
