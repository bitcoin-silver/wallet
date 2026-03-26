package top.bitcoinsilver.wallet2025

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import androidx.activity.enableEdgeToEdge
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity: FlutterFragmentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isNavigationBarContrastEnforced = false
        }

        createNotificationChannel()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager = getSystemService(NotificationManager::class.java)
            val transactionChannel = NotificationChannel(
                "btcs_transactions",
                "Bitcoin Silver Transactions",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Notifications for incoming Bitcoin Silver transactions"
                enableVibration(true)
                enableLights(true)
            }
            val priceAlertChannel = NotificationChannel(
                "btcs_price_alerts",
                "BTCS Price Alerts",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Notifications for significant BTCS price changes"
                enableVibration(true)
                enableLights(true)
            }
            notificationManager.createNotificationChannel(transactionChannel)
            notificationManager.createNotificationChannel(priceAlertChannel)
        }
    }
}
