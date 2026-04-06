package com.clipulse.android.ui.login

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.clipulse.android.data.remote.ApiError
import com.clipulse.android.data.remote.SupabaseClient
import com.clipulse.android.data.remote.TokenStore
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

data class LoginUiState(
    val isLoading: Boolean = false,
    val error: String? = null,
    val isLoggedIn: Boolean = false,
    val showOtpInput: Boolean = false,
    val otpEmail: String = "",
)

@HiltViewModel
class LoginViewModel @Inject constructor(
    private val supabase: SupabaseClient,
    private val tokenStore: TokenStore,
) : ViewModel() {

    private val _state = MutableStateFlow(LoginUiState(isLoggedIn = tokenStore.isLoggedIn))
    val state: StateFlow<LoginUiState> = _state

    fun signInWithGoogle(idToken: String, name: String?, email: String?) {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            try {
                supabase.signInWithGoogle(idToken, name, email)
                _state.value = _state.value.copy(isLoading = false, isLoggedIn = true)
            } catch (e: Exception) {
                _state.value = _state.value.copy(isLoading = false, error = e.message)
            }
        }
    }

    fun sendOTP(email: String) {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            try {
                supabase.sendOTP(email)
                _state.value = _state.value.copy(
                    isLoading = false,
                    showOtpInput = true,
                    otpEmail = email,
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(isLoading = false, error = e.message)
            }
        }
    }

    fun verifyOTP(code: String) {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            try {
                supabase.verifyOTP(_state.value.otpEmail, code)
                _state.value = _state.value.copy(isLoading = false, isLoggedIn = true)
            } catch (e: Exception) {
                _state.value = _state.value.copy(isLoading = false, error = e.message)
            }
        }
    }

    fun signInWithPassword(email: String, password: String) {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            try {
                supabase.signInWithPassword(email, password)
                _state.value = _state.value.copy(isLoading = false, isLoggedIn = true)
            } catch (e: Exception) {
                _state.value = _state.value.copy(isLoading = false, error = e.message)
            }
        }
    }

    fun enterDemoMode() {
        tokenStore.isDemoMode = true
        _state.value = _state.value.copy(isLoggedIn = true)
    }

    fun tryRestoreSession() {
        if (tokenStore.isDemoMode) {
            _state.value = _state.value.copy(isLoggedIn = true)
            return
        }
        if (!tokenStore.isLoggedIn) return
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true)
            try {
                supabase.me()
                _state.value = _state.value.copy(isLoading = false, isLoggedIn = true)
            } catch (e: ApiError.TokenExpired) {
                // Confirmed auth failure — clear credentials
                tokenStore.clear()
                _state.value = _state.value.copy(isLoading = false, isLoggedIn = false)
            } catch (e: ApiError.Http) {
                if (e.code == 401 || e.code == 403) {
                    tokenStore.clear()
                    _state.value = _state.value.copy(isLoading = false, isLoggedIn = false)
                } else {
                    // Transient error — keep tokens, proceed as logged in
                    _state.value = _state.value.copy(isLoading = false, isLoggedIn = true,
                        error = "Offline — using cached session")
                }
            } catch (_: Exception) {
                // Network error — keep tokens, proceed as logged in
                _state.value = _state.value.copy(isLoading = false, isLoggedIn = true,
                    error = "Offline — using cached session")
            }
        }
    }
}
