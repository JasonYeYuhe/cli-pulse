import SwiftUI
import CLIPulseCore

/// Team management view — create teams, manage members, view invites.
struct TeamView: View {
    @EnvironmentObject var appState: AppState

    @State private var teams: [TeamDTO] = []
    @State private var selectedTeam: TeamDetailDTO?
    @State private var teamUsage: TeamUsageSummaryDTO?
    @State private var isLoading = false
    @State private var error: String?
    @State private var showCreateSheet = false
    @State private var showInviteSheet = false
    @State private var newTeamName = ""
    @State private var inviteEmail = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Teams")
                    .font(.headline)
                Spacer()
                Button(action: { showCreateSheet = true }) {
                    Image(systemName: "plus.circle")
                }
                .disabled(!appState.subscriptionManager.isProOrAbove)
            }

            if !appState.subscriptionManager.isProOrAbove {
                HStack {
                    Image(systemName: "lock.fill")
                    Text("Team features require Pro or Team subscription")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if teams.isEmpty {
                Text("No teams yet. Create one to get started.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(teams) { team in
                    TeamRow(team: team) {
                        Task { await loadTeamDetails(team.id) }
                    }
                }
            }

            if let detail = selectedTeam {
                Divider()
                let currentUserId = appState.api.userId ?? ""
                let callerIsOwner = detail.team.owner_id == currentUserId
                let callerIsAdmin = detail.members.first(where: { $0.user_id == currentUserId })?.role == "admin"
                let canManage = callerIsOwner || callerIsAdmin

                TeamDetailView(
                    detail: detail,
                    usage: teamUsage,
                    canManage: canManage,
                    isOwner: callerIsOwner,
                    onInvite: { showInviteSheet = true },
                    onRemove: { userId in
                        Task { await removeMember(teamId: detail.team.id, userId: userId) }
                    },
                    onRoleChange: { userId, role in
                        Task { await changeRole(teamId: detail.team.id, userId: userId, role: role) }
                    }
                )
            }

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .task { await loadTeams() }
        .sheet(isPresented: $showCreateSheet) {
            CreateTeamSheet(name: $newTeamName) {
                Task { await createTeam() }
            }
        }
        .sheet(isPresented: $showInviteSheet) {
            InviteSheet(email: $inviteEmail) {
                if let teamId = selectedTeam?.team.id {
                    Task { await inviteMember(teamId: teamId) }
                }
            }
        }
    }

    // MARK: - Actions

    private func loadTeams() async {
        isLoading = true
        do {
            teams = try await appState.api.myTeams()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func loadTeamDetails(_ teamId: String) async {
        do {
            selectedTeam = try await appState.api.teamDetails(teamId: teamId)
            teamUsage = try await appState.api.teamUsageSummary(teamId: teamId)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func createTeam() async {
        guard !newTeamName.isEmpty else { return }
        do {
            let team = try await appState.api.createTeam(name: newTeamName)
            teams.append(team)
            newTeamName = ""
            showCreateSheet = false
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func inviteMember(teamId: String) async {
        guard !inviteEmail.isEmpty else { return }
        do {
            try await appState.api.inviteMember(teamId: teamId, email: inviteEmail)
            inviteEmail = ""
            showInviteSheet = false
            await loadTeamDetails(teamId)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func removeMember(teamId: String, userId: String) async {
        do {
            try await appState.api.removeMember(teamId: teamId, userId: userId)
            await loadTeamDetails(teamId)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func changeRole(teamId: String, userId: String, role: String) async {
        do {
            try await appState.api.updateMemberRole(teamId: teamId, userId: userId, role: role)
            await loadTeamDetails(teamId)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Subviews

private struct TeamRow: View {
    let team: TeamDTO
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: "person.3.fill")
                    .foregroundStyle(.blue)
                VStack(alignment: .leading) {
                    Text(team.name).font(.body)
                    if let role = team.role {
                        Text(role.capitalized).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

private struct TeamDetailView: View {
    let detail: TeamDetailDTO
    let usage: TeamUsageSummaryDTO?
    let canManage: Bool
    let isOwner: Bool
    let onInvite: () -> Void
    let onRemove: (String) -> Void
    let onRoleChange: (String, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(detail.team.name).font(.headline)
                Spacer()
                if canManage {
                    Button("Invite", action: onInvite)
                        .font(.caption)
                }
            }

            if let usage {
                HStack(spacing: 16) {
                    Label("\(usage.member_count) members", systemImage: "person.2")
                    Label("\(usage.total_usage) tokens", systemImage: "chart.bar")
                    Label(String(format: "$%.2f", usage.total_cost), systemImage: "dollarsign.circle")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Text("Members").font(.subheadline).padding(.top, 4)
            ForEach(detail.members) { member in
                HStack {
                    VStack(alignment: .leading) {
                        Text(member.name.isEmpty ? member.email : member.name).font(.body)
                        Text(member.role.capitalized).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if member.role != "owner" && canManage {
                        Menu {
                            if isOwner {
                                Button("Make Admin") { onRoleChange(member.user_id, "admin") }
                                Button("Make Member") { onRoleChange(member.user_id, "member") }
                                Divider()
                            }
                            Button("Remove", role: .destructive) { onRemove(member.user_id) }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }

            if !detail.invites.isEmpty {
                Text("Pending Invites").font(.subheadline).padding(.top, 4)
                ForEach(detail.invites) { invite in
                    HStack {
                        Text(invite.email).font(.body)
                        Spacer()
                        Text("Pending").font(.caption).foregroundStyle(.orange)
                    }
                }
            }
        }
    }
}

private struct CreateTeamSheet: View {
    @Binding var name: String
    let onCreate: () -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Create Team").font(.headline)
            TextField("Team Name", text: $name)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Create", action: onCreate).disabled(name.isEmpty)
            }
        }
        .padding()
        .frame(width: 300)
    }
}

private struct InviteSheet: View {
    @Binding var email: String
    let onInvite: () -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Invite Member").font(.headline)
            TextField("Email Address", text: $email)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Send Invite", action: onInvite).disabled(email.isEmpty)
            }
        }
        .padding()
        .frame(width: 300)
    }
}
