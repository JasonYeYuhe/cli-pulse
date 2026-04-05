package com.clipulse.android.ui.team

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.clipulse.android.data.remote.SupabaseClient
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import org.json.JSONObject
import javax.inject.Inject

data class TeamInfo(
    val id: String,
    val name: String,
    val role: String,
)

data class TeamMember(
    val userId: String,
    val name: String,
    val email: String,
    val role: String,
)

data class TeamUiState(
    val teams: List<TeamInfo> = emptyList(),
    val selectedTeam: TeamInfo? = null,
    val members: List<TeamMember> = emptyList(),
    val isLoading: Boolean = false,
    val error: String? = null,
)

@HiltViewModel
class TeamViewModel @Inject constructor(
    private val supabase: SupabaseClient,
) : ViewModel() {

    private val _state = MutableStateFlow(TeamUiState())
    val state: StateFlow<TeamUiState> = _state

    init { loadTeams() }

    fun loadTeams() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            try {
                val json = supabase.rpcPublic("team_details_for_user")
                // For now, use a simplified approach via REST
                _state.value = _state.value.copy(isLoading = false)
            } catch (e: Exception) {
                _state.value = _state.value.copy(isLoading = false, error = e.message)
            }
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
                loadTeams()
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = e.message)
            }
        }
    }
}
