// ContentView.swift
// skilld — menubar app
//
// Popover list UI: search field, per-row Install / Remove / Update buttons,
// installed indicator, update badge.

import SwiftUI

// MARK: - Root view

struct ContentView: View {
    @State private var store = SkillStore()

    var body: some View {
        VStack(spacing: 0) {
            HeaderView()
            SearchBarView(text: $store.searchText)
            Divider().opacity(0.3)
            SkillListView(store: store)
            if let err = store.lastError {
                ErrorBannerView(message: err) { store.lastError = nil }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .frame(width: 360, height: 480)
    }
}

// MARK: - Header

private struct HeaderView: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "brain.filled.head.profile")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.purple, .indigo],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text("skilld")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.purple, .indigo],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            Text("library")
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(Color.secondary.opacity(0.6))
                .font(.system(size: 13))
            TextField("Search skills…", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
            if !text.isEmpty {
                Button {
                    text = ""
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

// MARK: - List

private struct SkillListView: View {
    let store: SkillStore

    var body: some View {
        if store.filteredSkills.isEmpty {
            ContentUnavailableView(
                "No skills found",
                systemImage: "magnifyingglass",
                description: Text("Try a different search term.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.filteredSkills) { skill in
                        SkillRowView(skill: skill, store: store)
                        if skill.id != store.filteredSkills.last?.id {
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

// MARK: - Row

private struct SkillRowView: View {
    let skill: SkillEntry
    let store: SkillStore

    @State private var isHovered = false

    private var installed: Bool { store.isInstalled(skill) }
    private var hasUpdate: Bool { installed && store.updateAvailable(skill) }
    private var opState: OperationState? { store.operationState[skill.id] }
    private var isWorking: Bool { opState == .inProgress }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {

            // Installed indicator dot
            Circle()
                .fill(installed ? Color.green : Color.clear)
                .stroke(installed ? Color.green : Color.secondary.opacity(0.3), lineWidth: 1.2)
                .frame(width: 8, height: 8)
                .padding(.top, 5)

            // Text content
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(skill.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)

                    if hasUpdate {
                        UpdateBadge()
                    }
                }

                Text(skill.description)
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            // Action button(s)
            ActionButtons(skill: skill, store: store, installed: installed,
                          hasUpdate: hasUpdate, isWorking: isWorking)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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

// MARK: - Action buttons

private struct ActionButtons: View {
    let skill: SkillEntry
    let store: SkillStore
    let installed: Bool
    let hasUpdate: Bool
    let isWorking: Bool

    var body: some View {
        HStack(spacing: 6) {
            if isWorking {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 24, height: 24)
            } else if installed {
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
        case .primary: return .white
        case .destructive: return isHovered ? .white : Color.red.opacity(0.8)
        case .update: return .white
        }
    }

    private var gradient: LinearGradient {
        switch style {
        case .primary:
            return LinearGradient(colors: [.purple, .indigo], startPoint: .leading, endPoint: .trailing)
        case .destructive:
            return LinearGradient(
                colors: isHovered ? [Color.red.opacity(0.9), Color.red.opacity(0.7)] : [Color.red.opacity(0.12), Color.red.opacity(0.12)],
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
                .background(Capsule().fill(gradient).opacity(isHovered && style != .destructive ? 0.85 : 1))
                .scaleEffect(isHovered ? 0.97 : 1)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.spring(duration: 0.15), value: isHovered)
    }
}

// MARK: - Error banner

private struct ErrorBannerView: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 12))
            Text(message)
                .font(.system(size: 11))
                .foregroundColor(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.1))
        .overlay(Divider().frame(maxWidth: .infinity, maxHeight: 1), alignment: .top)
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
