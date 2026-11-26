package com.example.unsync

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private var launchPayload: String? = null
    private val backupDocuments by lazy { BackupDocuments(this) }

    override fun onCreate(savedInstanceState: Bundle?) {
        Log.i(
            "StartupLatency",
            "[STARTUP_LATENCY] ${System.currentTimeMillis()} android_activity_creation"
        )
        launchPayload = notificationPayloadFromIntent()
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "uk.unsync.messenger/launch_intent"
        ).setMethodCallHandler { call, result ->
            if (call.method == "openAxonForum") {
                try {
                    val intent = packageManager.getLaunchIntentForPackage("com.unsync.axon")
                        ?: throw IllegalStateException("Axon browser is not installed")
                    startActivity(intent)
                    result.success(true)
                } catch (error: Exception) {
                    result.error("axon_unavailable", error.message ?: "Could not open Axon", null)
                }
            } else if (call.method == "initialNotificationPayload") {
                result.success(launchPayload)
            } else {
                result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BackupDocuments.CHANNEL
        ).setMethodCallHandler { call, result -> backupDocuments.handle(call, result) }
    }

    @Deprecated("Activity results for the backup folder and file pickers")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (backupDocuments.onActivityResult(requestCode, resultCode, data)) return
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun getInitialRoute(): String {
        val payload = notificationPayloadFromIntent()
        return if (payload != null) {
            "/incoming-call?payload=${Uri.encode(payload)}"
        } else {
            super.getInitialRoute() ?: "/"
        }
    }

    private fun notificationPayloadFromIntent(): String? {
        val currentIntent = intent ?: return null
        if (currentIntent.action != "SELECT_NOTIFICATION") return null
        return currentIntent.getStringExtra("payload")
    }
}
