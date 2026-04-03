package com.clipulse.android.data.model

import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class AuthResponse(
    val access_token: String,
    val refresh_token: String? = null,
    val user: UserDTO,
    val paired: Boolean,
)

@JsonClass(generateAdapter = true)
data class UserDTO(
    val id: String,
    val name: String,
    val email: String,
)
