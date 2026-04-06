package com.clipulse.android.billing

import android.app.Activity
import android.content.Context
import com.android.billingclient.api.*
import com.clipulse.android.data.remote.SupabaseClient
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

data class SubscriptionState(
    val tier: String = "free", // free, pro, team
    val isActive: Boolean = false,
    val isPending: Boolean = false,
    val products: List<ProductDetails> = emptyList(),
    val isLoading: Boolean = false,
)

class BillingManager(
    private val context: Context,
    private val supabase: SupabaseClient,
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

    private val scope = CoroutineScope(Dispatchers.IO)
    private val reconnectAttempts = AtomicInteger(0)
    private val isReconnecting = AtomicBoolean(false)

    private var billingClient: BillingClient = BillingClient.newBuilder(context)
        .setListener(this)
        .enablePendingPurchases(PendingPurchasesParams.newBuilder().enableOneTimeProducts().build())
        .build()

    fun connect() {
        billingClient.startConnection(object : BillingClientStateListener {
            override fun onBillingSetupFinished(result: BillingResult) {
                if (result.responseCode == BillingClient.BillingResponseCode.OK) {
                    reconnectAttempts.set(0)
                    isReconnecting.set(false)
                    queryProducts()
                    queryPurchases()
                }
            }

            override fun onBillingServiceDisconnected() {
                if (isReconnecting.compareAndSet(false, true)) {
                    scope.launch {
                        val attempt = reconnectAttempts.getAndIncrement()
                        val delay = minOf(attempt * 2000L, 30_000L)
                        kotlinx.coroutines.delay(delay)
                        connect() // Reconnect using the same method
                        isReconnecting.set(false)
                    }
                }
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
                // Prioritize PURCHASED over PENDING (a user may have both)
                val activePurchase = purchases.firstOrNull {
                    it.purchaseState == Purchase.PurchaseState.PURCHASED
                }
                if (activePurchase != null) {
                    val productId = activePurchase.products.firstOrNull() ?: ""

                    // Enter pending state — do NOT grant tier until server verifies
                    _state.value = _state.value.copy(isPending = true, isLoading = true)

                    // Acknowledge if needed, then validate on server
                    if (!activePurchase.isAcknowledged) {
                        val ackParams = AcknowledgePurchaseParams.newBuilder()
                            .setPurchaseToken(activePurchase.purchaseToken)
                            .build()
                        billingClient.acknowledgePurchase(ackParams) { ackResult ->
                            if (ackResult.responseCode == BillingClient.BillingResponseCode.OK) {
                                validateOnServer(activePurchase.purchaseToken, productId)
                            } else {
                                _state.value = _state.value.copy(isPending = false, isLoading = false)
                            }
                        }
                    } else {
                        validateOnServer(activePurchase.purchaseToken, productId)
                    }
                } else {
                    // No active purchase — check for pending
                    val hasPending = purchases.any {
                        it.purchaseState == Purchase.PurchaseState.PENDING
                    }
                    _state.value = _state.value.copy(
                        tier = "free",
                        isActive = false,
                        isPending = hasPending,
                    )
                }
            }
        }
    }

    private fun validateOnServer(purchaseToken: String, productId: String, retryCount: Int = 0) {
        scope.launch {
            try {
                val result = supabase.validateReceipt(purchaseToken, productId)
                if (result.verified) {
                    _state.value = _state.value.copy(
                        tier = result.tier,
                        isActive = true,
                        isPending = false,
                        isLoading = false,
                    )
                } else if (result.isNetworkError && retryCount < 3) {
                    // Network error — retry with backoff
                    kotlinx.coroutines.delay((retryCount + 1) * 5000L)
                    validateOnServer(purchaseToken, productId, retryCount + 1)
                } else if (result.isNetworkError) {
                    // Retries exhausted due to network — do NOT downgrade, keep current tier
                    _state.value = _state.value.copy(
                        isPending = false,
                        isLoading = false,
                    )
                } else {
                    // Server explicitly rejected the purchase — revert to free
                    _state.value = _state.value.copy(
                        tier = "free",
                        isActive = false,
                        isPending = false,
                        isLoading = false,
                    )
                }
            } catch (_: Exception) {
                // Unexpected error — stay pending, will retry on next queryPurchases
                _state.value = _state.value.copy(
                    isPending = true,
                    isLoading = false,
                )
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

    fun restorePurchases() {
        queryPurchases()
    }

    override fun onPurchasesUpdated(result: BillingResult, purchases: List<Purchase>?) {
        if (result.responseCode == BillingClient.BillingResponseCode.OK && purchases != null) {
            queryPurchases()
        }
    }

    fun disconnect() {
        billingClient.endConnection()
    }
}
