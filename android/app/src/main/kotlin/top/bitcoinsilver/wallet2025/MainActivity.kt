package top.bitcoinsilver.wallet2025

import android.app.NotificationChannel
import android.app.NotificationManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.FileOutputStream

class MainActivity: FlutterFragmentActivity() {

    // ── File export ──────────────────────────────────────────────────────────
    // Why this exists: FilePicker.saveFile (android_file_picker 1.1.0,
    // FileUtils.writeBytesData) writes with contentResolver.openOutputStream(uri),
    // i.e. mode "w". On Android 10+ many document providers (Downloads, local
    // storage, some cloud drives) do NOT truncate in mode "w". When the user
    // saves over an existing, longer BTCS_contacts.btcs, the new JSON is written
    // over the start of the old file and the old file's tail stays behind, e.g.
    //   {..."contacts":[...]}"username":"Raul.A",...}]}
    // That file is invalid JSON and neither wallet could import it.
    // This channel opens the chosen document with "wt" (write + truncate) and
    // checks the final size. Used by lib/services/file_export_service.dart.
    private val exportChannelName = "top.bitcoinsilver.wallet/file_export"
    private var pendingExportBytes: ByteArray? = null
    private var pendingExportResult: MethodChannel.Result? = null

    // application/octet-stream keeps the file name as given (no ".bin"/".json"
    // extension appended by the document provider).
    private val createDocument =
        registerForActivityResult(ActivityResultContracts.CreateDocument("application/octet-stream")) { uri ->
            onExportTargetChosen(uri)
        }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, exportChannelName)
            .setMethodCallHandler { call, result ->
                if (call.method != "saveFile") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val fileName = call.argument<String>("fileName")
                val bytes = call.argument<ByteArray>("bytes")
                if (fileName.isNullOrBlank() || bytes == null) {
                    result.error("bad_args", "fileName and bytes are required", null)
                    return@setMethodCallHandler
                }
                if (pendingExportResult != null) {
                    result.error("already_active", "An export is already in progress", null)
                    return@setMethodCallHandler
                }
                pendingExportBytes = bytes
                pendingExportResult = result
                createDocument.launch(fileName)
            }
    }

    private fun onExportTargetChosen(uri: Uri?) {
        val result = pendingExportResult
        val bytes = pendingExportBytes
        pendingExportResult = null
        pendingExportBytes = null
        // result is null if the activity was recreated while the system file
        // dialog was open; the Dart call is gone, so there is nobody to answer.
        if (result == null) return
        if (uri == null || bytes == null) {
            result.success(null) // user cancelled
            return
        }

        val mainHandler = Handler(Looper.getMainLooper())
        Thread {
            try {
                writeTruncating(uri, bytes)
                mainHandler.post { result.success(uri.toString()) }
            } catch (e: Exception) {
                mainHandler.post { result.error("write_failed", e.message ?: "Could not write file", null) }
            }
        }.start()
    }

    private fun writeTruncating(uri: Uri, bytes: ByteArray) {
        try {
            val out = contentResolver.openOutputStream(uri, "wt")
                ?: throw IllegalStateException("Could not open the file for writing")
            out.use { it.write(bytes) }
        } catch (e: IllegalStateException) {
            throw e
        } catch (e: Exception) {
            // Some providers reject the "wt" mode. Fall back to read-write and
            // truncate explicitly, so old bytes can never survive.
            val pfd = contentResolver.openFileDescriptor(uri, "rw")
                ?: throw IllegalStateException("Could not open the file for writing")
            pfd.use {
                FileOutputStream(it.fileDescriptor).use { out ->
                    out.channel.truncate(0)
                    out.write(bytes)
                    out.flush()
                }
            }
        }

        // Verify: a size larger than what we wrote means leftovers survived.
        // statSize is -1 when the provider cannot tell; skip the check then.
        val size = contentResolver.openFileDescriptor(uri, "r")?.use { it.statSize } ?: -1L
        if (size >= 0 && size != bytes.size.toLong()) {
            throw IllegalStateException("Saved file has $size bytes, expected ${bytes.size}")
        }
    }

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
                "Bitcoin Silver Price Alerts",
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
