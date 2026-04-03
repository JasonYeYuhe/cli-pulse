package com.clipulse.android.billing

import android.app.Activity
import android.content.Context
import com.android.billingclient.api.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

data class SubscriptionState(
    val tier: String = "free", // free, pro, team
    val isActive: Boolean = false,
    val products: List<ProductDetails> = emptyList(),
    val isLoading: Boolean = false,
)

class BillingManager(
    private val context: Context,
) : PurchasesUpdatedListener {

    companion object {
        const val PRO_MONTHLY = "com.clipulse.pro.monthly"
        const val PRO_YEARLY = "com.clipulse.pro.yearly"
        const val TEAM_MONTHLY = "com.clipulse.team.monthly"
        const val TEAM_YEARLY = "com.clipulse.team.yearly"

        private val ALL_PRODUCT_IDS = listOf(PRO_MONTHLY, PRO_YEARLY, TEAM_MONTHLY, TEAM_YEARLY)
    }

    private val _state = MutableStateFlow(SubscriptionState())
    val state: StateFlow<SubscriptionState> = _state

    private var billingClient: BillingClient = BillingClient.newBuilder(context)
        .setListener(this)
        .enablePendingPurchases(PendingPurchasesParams.newBuilder().enableOneTimeProducts().build())
        .build()

    fun connect() {
        billingClient.startConnection(object : BillingClientStateListener {
            override fun onBillingSetupFinished(result: BillingResult) {
                if (result.responseCode == BillingClient.BillingResponseCode.OK) {
                    queryProducts()
                    queryPurchases()
                }
            }

            override fun onBillingServiceDisconnected() {
                // Retry on next user action
            }
        })
    }

    private fun queryProducts() {
        val params = QueryProductDetailsParams.newBuilder()
            .setProductList(
                ALL_PRODUCT_IDS.map { id ->
                    QueryProductDetailsParams.Product.newBuilder()
                        .setProductId(id)
                        .setProductType(BillingClient.ProductType.SUBS)
                        .build()
                }
            )
            .build()

        billingClient.queryProductDetailsAsync(params) { result, productDetailsList ->
            if (result.responseCode == BillingClient.BillingResponseCode.OK) {
                _state.value = _state.value.copy(products = productDetailsList)
            }
        }
    }

    private fun queryPurchases() {
        val params = QueryPurchasesParams.newBuilder()
            .setProductType(BillingClient.ProductType.SUBS)
            .build()

        billingClient.queryPurchasesAsync(params) { result, purchases ->
            if (result.responseCode == BillingClient.BillingResponseCode.OK) {
                val activePurchase = purchases.firstOrNull { it.purchaseState == Purchase.PurchaseState.PURCHASED }
                if (activePurchase != null) {
                    val productId = activePurchase.products.firstOrNull() ?: ""
                    val tier = when {
                        productId.contains("team") -> "team"
                        productId.contains("pro") -> "pro"
                        else -> "free"
                    }
                    _state.value = _state.value.copy(tier = tier, isActive = true)

                    // Acknowledge if needed
                    if (!activePurchase.isAcknowledged) {
                        val ackParams = AcknowledgePurchaseParams.newBuilder()
                            .setPurchaseToken(activePurchase.purchaseToken)
                            .build()
                        billingClient.acknowledgePurchase(ackParams) { }
                    }
                } else {
                    _state.value = _state.value.copy(tier = "free", isActive = false)
                }
            }
        }
    }

    fun purchase(activity: Activity, productDetails: ProductDetails) {
        val offerToken = productDetails.subscriptionOfferDetails?.firstOrNull()?.offerToken ?: return
        val params = BillingFlowParams.newBuilder()
            .setProductDetailsParamsList(
                listOf(
                    BillingFlowParams.ProductDetailsParams.newBuilder()
                        .setProductDetails(productDetails)
                        .setOfferToken(offerToken)
                        .build()
                )
            )
            .build()
        billingClient.launchBillingFlow(activity, params)
    }

    override fun onPurchasesUpdated(result: BillingResult, purchases: List<Purchase>?) {
        if (result.responseCode == BillingClient.BillingResponseCode.OK && purchases != null) {
            queryPurchases() // Re-check to update state
        }
    }

    fun disconnect() {
        billingClient.endConnection()
    }
}
