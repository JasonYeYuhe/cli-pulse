package com.clipulse.android.ui.navigation

import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.clipulse.android.ui.alerts.AlertsScreen
import com.clipulse.android.ui.login.LoginScreen
import com.clipulse.android.ui.overview.OverviewScreen
import com.clipulse.android.ui.providers.ProviderDetailRoute
import com.clipulse.android.ui.providers.ProvidersScreen
import com.clipulse.android.ui.sessions.SessionsScreen
import com.clipulse.android.ui.settings.SettingsScreen

enum class Screen(val route: String, val label: String, val icon: ImageVector) {
    Overview("overview", "Overview", Icons.Default.Dashboard),
    Providers("providers", "Providers", Icons.Default.Dns),
    Sessions("sessions", "Sessions", Icons.AutoMirrored.Filled.List),
    Alerts("alerts", "Alerts", Icons.Default.Notifications),
    Settings("settings", "Settings", Icons.Default.Settings),
}

@Composable
fun AppNavigation() {
    val navController = rememberNavController()
    var isLoggedIn by remember { mutableStateOf(false) }

    if (!isLoggedIn) {
        LoginScreen(onLoggedIn = { isLoggedIn = true })
        return
    }

    val tabs = Screen.entries
    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentDestination = navBackStackEntry?.destination

    Scaffold(
        bottomBar = {
            // Hide bottom bar on detail screens
            val isTopLevel = tabs.any { currentDestination?.route == it.route }
            if (isTopLevel) {
                NavigationBar {
                    tabs.forEach { screen ->
                        NavigationBarItem(
                            icon = { Icon(screen.icon, contentDescription = screen.label) },
                            label = { Text(screen.label) },
                            selected = currentDestination?.hierarchy?.any { it.route == screen.route } == true,
                            onClick = {
                                navController.navigate(screen.route) {
                                    popUpTo(navController.graph.findStartDestination().id) {
                                        saveState = true
                                    }
                                    launchSingleTop = true
                                    restoreState = true
                                }
                            },
                        )
                    }
                }
            }
        },
    ) { innerPadding ->
        NavHost(
            navController = navController,
            startDestination = Screen.Overview.route,
            modifier = Modifier.padding(innerPadding),
        ) {
            composable(Screen.Overview.route) { OverviewScreen() }
            composable(Screen.Providers.route) {
                ProvidersScreen(
                    onProviderClick = { providerName ->
                        navController.navigate("provider_detail/$providerName")
                    },
                )
            }
            composable(
                route = "provider_detail/{providerName}",
                arguments = listOf(navArgument("providerName") { type = NavType.StringType }),
            ) { backStackEntry ->
                val providerName = backStackEntry.arguments?.getString("providerName") ?: ""
                ProviderDetailRoute(
                    providerName = providerName,
                    onBack = { navController.popBackStack() },
                )
            }
            composable(Screen.Sessions.route) { SessionsScreen() }
            composable(Screen.Alerts.route) { AlertsScreen() }
            composable(Screen.Settings.route) {
                SettingsScreen(onSignOut = { isLoggedIn = false })
            }
        }
    }
}
