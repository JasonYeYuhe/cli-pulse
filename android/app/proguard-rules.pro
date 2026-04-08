# Moshi
-keep class com.clipulse.android.data.model.** { *; }
-keepclassmembers class com.clipulse.android.data.model.** { *; }

# OkHttp
-dontwarn okhttp3.internal.platform.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**

# Room — keep entities and DAOs
-keep class com.clipulse.android.data.local.** { *; }
-keepclassmembers class com.clipulse.android.data.local.** { *; }

# Hilt — keep generated components
-keep class dagger.hilt.** { *; }
-dontwarn dagger.hilt.internal.**

# Coroutines
-dontwarn kotlinx.coroutines.debug.**

# Firebase Messaging
-keep class com.google.firebase.messaging.** { *; }

# Credentials (Google Sign-In)
-keep class com.google.android.libraries.identity.** { *; }
-keep class androidx.credentials.** { *; }
