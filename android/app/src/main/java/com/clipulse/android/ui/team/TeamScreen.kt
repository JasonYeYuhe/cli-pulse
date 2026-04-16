package com.clipulse.android.ui.team

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.clipulse.android.R
import com.clipulse.android.ui.navigation.LocalSnackbarHostState

@Composable
fun TeamScreen(
    viewModel: TeamViewModel = hiltViewModel(),
    onBack: () -> Unit = {},
) {
    val state by viewModel.state.collectAsState()
    val snackbar = LocalSnackbarHostState.current
    LaunchedEffect(state.error) {
        state.error?.let { snackbar.showSnackbar(it) }
    }
    var showCreateDialog by remember { mutableStateOf(false) }
    var showInviteDialog by remember { mutableStateOf(false) }
    var newTeamName by remember { mutableStateOf("") }
    var inviteEmail by remember { mutableStateOf("") }

    Scaffold(
        topBar = {
            @OptIn(ExperimentalMaterial3Api::class)
            TopAppBar(
                title = { Text(state.selectedTeam?.name ?: stringResource(R.string.settings_teams)) },
                navigationIcon = {
                    IconButton(onClick = {
                        if (state.selectedTeam != null) {
                            viewModel.deselectTeam()
                        } else {
                            onBack()
                        }
                    }) {
                        Icon(Icons.Filled.ArrowBack, contentDescription = stringResource(R.string.back))
                    }
                },
                actions = {
                    if (state.selectedTeam != null) {
                        IconButton(onClick = { showInviteDialog = true }) {
                            Icon(Icons.Filled.PersonAdd, contentDescription = stringResource(R.string.team_invite_member))
                        }
                    } else {
                        IconButton(onClick = { showCreateDialog = true }) {
                            Icon(Icons.Filled.Add, contentDescription = stringResource(R.string.team_create))
                        }
                    }
                },
            )
        },
    ) { padding ->
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(padding)
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
    ) {
        if (state.isLoading) {
            CircularProgressIndicator(modifier = Modifier.padding(16.dp))
        }

        if (state.selectedTeam != null) {
            // ── Member list ──
            if (state.members.isEmpty() && state.invites.isEmpty() && !state.isLoading) {
                Text(stringResource(R.string.team_no_members), style = MaterialTheme.typography.bodyMedium)
            }
            for (member in state.members) {
                MemberCard(
                    member = member,
                    isAdmin = state.selectedTeam?.role in listOf("owner", "admin"),
                    onRemove = { state.selectedTeam?.id?.let { teamId -> viewModel.removeMember(teamId, member.userId) } },
                    onChangeRole = { newRole -> state.selectedTeam?.id?.let { teamId -> viewModel.changeRole(teamId, member.userId, newRole) } },
                )
            }

            // ── Pending invites ──
            if (state.invites.isNotEmpty()) {
                Spacer(Modifier.height(16.dp))
                Text(
                    stringResource(R.string.team_pending_invites),
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(Modifier.height(4.dp))
                for (invite in state.invites) {
                    Card(modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
                        Row(
                            modifier = Modifier.padding(16.dp).fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Column(modifier = Modifier.weight(1f)) {
                                Text(invite.email, style = MaterialTheme.typography.titleSmall)
                                Text(
                                    invite.role,
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                            AssistChip(
                                onClick = {},
                                label = { Text(stringResource(R.string.team_pending)) },
                                colors = AssistChipDefaults.assistChipColors(
                                    containerColor = MaterialTheme.colorScheme.tertiaryContainer,
                                ),
                            )
                        }
                    }
                }
            }
        } else {
            // ── Team list ──
            if (state.teams.isEmpty() && !state.isLoading) {
                Card(modifier = Modifier.fillMaxWidth()) {
                    Column(modifier = Modifier.padding(16.dp)) {
                        Text(stringResource(R.string.team_no_teams), style = MaterialTheme.typography.titleMedium)
                        Spacer(Modifier.height(4.dp))
                        Text(
                            stringResource(R.string.team_no_teams_hint),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }

            for (team in state.teams) {
                Card(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 4.dp)
                        .clickable { viewModel.selectTeam(team) },
                ) {
                    Row(
                        modifier = Modifier.padding(16.dp).fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column {
                            Text(team.name, style = MaterialTheme.typography.titleMedium)
                            Text(
                                stringResource(R.string.team_role, team.role),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        Icon(Icons.Filled.ChevronRight, contentDescription = null)
                    }
                }
            }
        }

        state.error?.let { error ->
            Spacer(Modifier.height(8.dp))
            Text(error, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
        }
    }
    } // end Scaffold

    if (showCreateDialog) {
        AlertDialog(
            onDismissRequest = { showCreateDialog = false },
            title = { Text(stringResource(R.string.team_create)) },
            text = {
                OutlinedTextField(
                    value = newTeamName,
                    onValueChange = { newTeamName = it },
                    label = { Text(stringResource(R.string.team_name_hint)) },
                    singleLine = true,
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    viewModel.createTeam(newTeamName)
                    newTeamName = ""
                    showCreateDialog = false
                }) { Text(stringResource(R.string.create)) }
            },
            dismissButton = {
                TextButton(onClick = { showCreateDialog = false }) { Text(stringResource(R.string.cancel)) }
            },
        )
    }

    if (showInviteDialog) {
        AlertDialog(
            onDismissRequest = { showInviteDialog = false },
            title = { Text(stringResource(R.string.team_invite_member)) },
            text = {
                OutlinedTextField(
                    value = inviteEmail,
                    onValueChange = { inviteEmail = it },
                    label = { Text(stringResource(R.string.team_email_hint)) },
                    singleLine = true,
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    state.selectedTeam?.let { viewModel.inviteMember(it.id, inviteEmail) }
                    inviteEmail = ""
                    showInviteDialog = false
                }) { Text(stringResource(R.string.invite)) }
            },
            dismissButton = {
                TextButton(onClick = { showInviteDialog = false }) { Text(stringResource(R.string.cancel)) }
            },
        )
    }
}

@Composable
private fun MemberCard(
    member: TeamMember,
    isAdmin: Boolean,
    onRemove: () -> Unit,
    onChangeRole: (String) -> Unit,
) {
    var showRoleMenu by remember { mutableStateOf(false) }

    Card(modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
        Row(
            modifier = Modifier.padding(16.dp).fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    member.name.ifBlank { member.email },
                    style = MaterialTheme.typography.titleSmall,
                )
                Text(
                    member.email,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text(
                    member.role,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.primary,
                )
            }
            if (isAdmin && member.role != "owner") {
                Box {
                    IconButton(onClick = { showRoleMenu = true }) {
                        Icon(Icons.Filled.MoreVert, contentDescription = stringResource(R.string.team_manage_member))
                    }
                    DropdownMenu(expanded = showRoleMenu, onDismissRequest = { showRoleMenu = false }) {
                        if (member.role != "admin") {
                            DropdownMenuItem(
                                text = { Text(stringResource(R.string.team_make_admin)) },
                                onClick = { showRoleMenu = false; onChangeRole("admin") },
                            )
                        }
                        if (member.role != "member") {
                            DropdownMenuItem(
                                text = { Text(stringResource(R.string.team_make_member)) },
                                onClick = { showRoleMenu = false; onChangeRole("member") },
                            )
                        }
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.remove)) },
                            onClick = { showRoleMenu = false; onRemove() },
                        )
                    }
                }
            }
        }
    }
}
