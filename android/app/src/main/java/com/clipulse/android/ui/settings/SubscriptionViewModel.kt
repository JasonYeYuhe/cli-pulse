package com.clipulse.android.ui.settings

import android.app.Activity
import androidx.lifecycle.ViewModel
import com.android.billingclient.api.ProductDetails
import com.clipulse.android.billing.BillingManager
import com.clipulse.android.billing.SubscriptionState
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.StateFlow
import javax.inject.Inject

@HiltViewModel
class SubscriptionViewModel @Inject constructor(
    private val billingManager: BillingManager,
) : ViewModel() {

    val state: StateFlow<SubscriptionState> = billingManager.state

    init {
        billingManager.connect()
    }

    fun purchase(activity: Activity, productDetails: ProductDetails) {
        billingManager.purchase(activity, productDetails)
    }

    fun restore() {
        billingManager.restorePurchases()
    }

    override fun onCleared() {
        super.onCleared()
        billingManager.disconnect()
    }
}
