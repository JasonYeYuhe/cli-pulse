package com.clipulse.android.ui.login

import android.content.Intent
import android.net.Uri
import android.util.Log
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.credentials.CredentialManager
import androidx.credentials.GetCredentialRequest
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.hilt.navigation.compose.hiltViewModel
import com.google.android.libraries.identity.googleid.GetGoogleIdOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import kotlinx.coroutines.launch

/** Stores the PKCE verifier while the browser handles GitHub OAuth. */
private var pendingOAuthVerifier: String? = null

@Composable
fun LoginScreen(
    viewModel: LoginViewModel = hiltViewModel(),
    oauthCode: String? = null,
    onLoggedIn: () -> Unit,
) {
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    LaunchedEffect(Unit) { viewModel.tryRestoreSession() }
    LaunchedEffect(state.isLoggedIn) {
        if (state.isLoggedIn) onLoggedIn()
    }

    // Handle deep-link OAuth callback
    LaunchedEffect(oauthCode) {
        val code = oauthCode ?: return@LaunchedEffect
        val verifier = pendingOAuthVerifier ?: return@LaunchedEffect
        pendingOAuthVerifier = null
        viewModel.exchangeOAuthCode(code, verifier)
    }

    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var otpCode by remember { mutableStateOf("") }
    var showPasswordLogin by remember { mutableStateOf(false) }

    Surface(
        modifier = Modifier.fillMaxSize(),
        color = MaterialTheme.colorScheme.background,
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Text(
                "CLI Pulse",
                style = MaterialTheme.typography.headlineLarge,
                color = MaterialTheme.colorScheme.primary,
            )
            Spacer(Modifier.height(8.dp))
            Text(
                "Monitor your AI API usage",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(48.dp))

            if (state.isLoading) {
                CircularProgressIndicator()
                return@Column
            }

            state.error?.let { error ->
                Text(
                    error,
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodySmall,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.padding(bottom = 16.dp),
                )
            }

            if (state.showOtpInput) {
                // OTP verification
                Text("Code sent to ${state.otpEmail}", style = MaterialTheme.typography.bodyMedium)
                Spacer(Modifier.height(16.dp))
                OutlinedTextField(
                    value = otpCode,
                    onValueChange = { otpCode = it },
                    label = { Text("Verification Code") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                Spacer(Modifier.height(16.dp))
                Button(
                    onClick = { viewModel.verifyOTP(otpCode) },
                    modifier = Modifier.fillMaxWidth(),
                    enabled = otpCode.isNotBlank(),
                ) {
                    Text("Verify")
                }
            } else if (showPasswordLogin) {
                // Password login
                OutlinedTextField(
                    value = email,
                    onValueChange = { email = it },
                    label = { Text("Email") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                Spacer(Modifier.height(12.dp))
                OutlinedTextField(
                    value = password,
                    onValueChange = { password = it },
                    label = { Text("Password") },
                    visualTransformation = PasswordVisualTransformation(),
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                Spacer(Modifier.height(16.dp))
                Button(
                    onClick = { viewModel.signInWithPassword(email, password) },
                    modifier = Modifier.fillMaxWidth(),
                    enabled = email.isNotBlank() && password.isNotBlank(),
                ) {
                    Text("Sign In")
                }
                Spacer(Modifier.height(8.dp))
                TextButton(onClick = { showPasswordLogin = false }) {
                    Text("Back to email sign-in")
                }
            } else {
                // Email OTP flow (primary)
                OutlinedTextField(
                    value = email,
                    onValueChange = { email = it },
                    label = { Text("Email") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                Spacer(Modifier.height(16.dp))
                Button(
                    onClick = { viewModel.sendOTP(email) },
                    modifier = Modifier.fillMaxWidth(),
                    enabled = email.contains("@"),
                ) {
                    Text("Send Verification Code")
                }
                Spacer(Modifier.height(24.dp))
                HorizontalDivider()
                Spacer(Modifier.height(24.dp))

                // Google Sign-In via Credential Manager
                OutlinedButton(
                    onClick = {
                        scope.launch {
                            try {
                                val googleIdOption = GetGoogleIdOption.Builder()
                                    .setFilterByAuthorizedAccounts(false)
                                    .setServerClientId(com.clipulse.android.BuildConfig.GOOGLE_WEB_CLIENT_ID)
                                    .build()
                                val request = GetCredentialRequest.Builder()
                                    .addCredentialOption(googleIdOption)
                                    .build()
                                val credentialManager = CredentialManager.create(context)
                                val result = credentialManager.getCredential(context, request)
                                val credential = result.credential
                                val googleIdToken = GoogleIdTokenCredential.createFrom(credential.data)
                                viewModel.signInWithGoogle(
                                    idToken = googleIdToken.idToken,
                                    name = googleIdToken.displayName,
                                    email = googleIdToken.id,
                                )
                            } catch (_: GetCredentialCancellationException) {
                                // User cancelled
                            } catch (e: Exception) {
                                Log.w("LoginScreen", "Google Sign-In failed", e)
                            }
                        }
                    },
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text("Sign in with Google")
                }
                Spacer(Modifier.height(12.dp))

                // GitHub Sign-In via Supabase OAuth PKCE
                OutlinedButton(
                    onClick = {
                        val (url, verifier) = viewModel.oauthAuthorizeUrl("github")
                        // Store verifier so we can exchange the code when the deep link returns
                        pendingOAuthVerifier = verifier
                        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                    },
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text("Sign in with GitHub")
                }
                Spacer(Modifier.height(12.dp))
                TextButton(onClick = { showPasswordLogin = true }) {
                    Text("Sign in with password")
                }
                Spacer(Modifier.height(24.dp))
                TextButton(onClick = {
                    viewModel.enterDemoMode()
                }) {
                    Text("Try Demo", color = MaterialTheme.colorScheme.tertiary)
                }
            }
        }
    }
}
