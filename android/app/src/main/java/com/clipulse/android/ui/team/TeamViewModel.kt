package com.clipulse.android.ui.team

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.clipulse.android.data.remote.SupabaseClient
import com.clipulse.android.data.remote.TokenStore
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import org.json.JSONObject
import javax.inject.Inject

data class TeamMember(
    val userId: String,
    val name: String,
    val email: String,
    val role: String,
)

data class TeamInvite(
    val id: String,
    val email: String,
    val role: String,
    val createdAt: String,
)

data class TeamUiState(
    val teams: List<SupabaseClient.TeamInfo> = emptyList(),
    val selectedTeam: SupabaseClient.TeamInfo? = null,
    val members: List<TeamMember> = emptyList(),
    val invites: List<TeamInvite> = emptyList(),
    val isLoading: Boolean = false,
    val error: String? = null,
)

@HiltViewModel
class TeamViewModel @Inject constructor(
    private val supabase: SupabaseClient,
    private val tokenStore: TokenStore,
) : ViewModel() {

    private val _state = MutableStateFlow(TeamUiState())
    val state: StateFlow<TeamUiState> = _state

    init { loadTeams() }

    fun loadTeams() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            try {
                val userId = tokenStore.userId ?: return@launch
                val teams = supabase.fetchTeamsForUser(userId)
                _state.value = _state.value.copy(isLoading = false, teams = teams)
            } catch (e: Exception) {
                _state.value = _state.value.copy(isLoading = false, error = e.message)
            }
        }
    }

    fun selectTeam(team: SupabaseClient.TeamInfo) {
        _state.value = _state.value.copy(selectedTeam = team)
        loadTeamDetails(team.id)
    }

    fun deselectTeam() {
        _state.value = _state.value.copy(selectedTeam = null, members = emptyList(), invites = emptyList())
    }

    private fun loadTeamDetails(teamId: String) {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            try {
                val (rawMembers, rawInvites) = supabase.fetchTeamDetails(teamId)
                val members = rawMembers.map { TeamMember(it.userId, it.name, it.email, it.role) }
                val invites = rawInvites.map { TeamInvite(it.id, it.email, it.role, it.createdAt) }
                _state.value = _state.value.copy(isLoading = false, members = members, invites = invites)
            } catch (_: Exception) {
                // Fallback to members-only if team_details RPC is unavailable
                loadMembersFallback(teamId)
            }
        }
    }

    private suspend fun loadMembersFallback(teamId: String) {
        try {
            val raw = supabase.fetchTeamMembers(teamId)
            val members = raw.map { TeamMember(it.userId, it.name, it.email, it.role) }
            _state.value = _state.value.copy(isLoading = false, members = members, invites = emptyList())
        } catch (e: Exception) {
            _state.value = _state.value.copy(isLoading = false, error = e.message)
        }
    }

    fun createTeam(name: String) {
        viewModelScope.launch {
            try {
                val params = JSONObject().apply { put("p_name", name) }
                supabase.rpcPublic("create_team", params)
                loadTeams()
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = e.message)
            }
        }
    }

    fun inviteMember(teamId: String, email: String) {
        viewModelScope.launch {
            try {
                val params = JSONObject().apply {
                    put("p_team_id", teamId)
                    put("p_email", email)
                    put("p_role", "member")
                }
                supabase.rpcPublic("invite_member", params)
                loadTeamDetails(teamId)
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = e.message)
            }
        }
    }

    fun removeMember(teamId: String, userId: String) {
        viewModelScope.launch {
            try {
                val params = JSONObject().apply {
                    put("p_team_id", teamId)
                    put("p_user_id", userId)
                }
                supabase.rpcPublic("remove_member", params)
                loadTeamDetails(teamId)
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = e.message)
            }
        }
    }

    fun changeRole(teamId: String, userId: String, newRole: String) {
        viewModelScope.launch {
            try {
                supabase.updateMemberRole(teamId, userId, newRole)
                loadTeamDetails(teamId)
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = e.message)
            }
        }
    }
}
