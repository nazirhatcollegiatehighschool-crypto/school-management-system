package com.school.guardian_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.FileProvider
import java.io.File

/// Receives the PackageInstaller session status and surfaces it where the
/// user can ALWAYS act on it (notification + Dart callback):
/// - SUCCESS → "Update installed ✅ — tap to open"
/// - FAILURE → reason-specific text + tap re-opens the installer from the
///   staged file (FileProvider fallback), so the user is NEVER stranded on
///   a dead screen with no install option.
class InstallStatusReceiver : BroadcastReceiver() {
    companion object {
        const val TAG = "SchoolInstallStatus"
        const val CHANNEL_ID = "school_update_status"
        const val ACTION_STATUS = "com.school.guardian_app.INSTALL_STATUS"

        fun statusMessage(status: Int, msg: String?): String {
            return when (status) {
                PackageInstaller.STATUS_SUCCESS -> "Update installed ✅"
                PackageInstaller.STATUS_PENDING_USER_ACTION ->
                    "Update প্রস্তুত — installer dialog-এ Install/Update চাপুন।"
                PackageInstaller.STATUS_FAILURE_ABORTED -> "Install বাতিল হয়েছে। আবার চেষ্টা করুন।"
                PackageInstaller.STATUS_FAILURE_BLOCKED ->
                    "System blocked the install (${msg ?: "unknown-source/Play-Protect"}). Settings → Install unknown apps → Allow, তারপর আবার চেষ্টা করুন।"
                PackageInstaller.STATUS_FAILURE_CONFLICT ->
                    "এই APK-র signing key app-এর সঙ্গে মেলেনি। App uninstall করবেন না—তাতে data মুছে যেতে পারে। সঠিক key-তে sign করা update লাগবে।"
                PackageInstaller.STATUS_FAILURE_INCOMPATIBLE ->
                    "Incompatible: এই APK ফোনের Android version/CPU-তে চলে না।"
                PackageInstaller.STATUS_FAILURE_INVALID ->
                    "Invalid package — ফাইল corrupt। আবার download করুন।"
                PackageInstaller.STATUS_FAILURE_STORAGE ->
                    "জায়গা নেই — storage খালি করে আবার চেষ্টা করুন।"
                else -> "Install ব্যর্থ (code $status): ${msg ?: "অজানা কারণ"}। আবার চেষ্টা করুন।"
            }
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, -999)
        val msg = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
        val apkPath = intent.getStringExtra("apkPath")
        Log.i(TAG, "status=$status msg=$msg apk=$apkPath")

        if (status == PackageInstaller.STATUS_PENDING_USER_ACTION) {
            val confirmationIntent = pendingUserActionIntent(intent)
            if (confirmationIntent == null) {
                Log.e(TAG, "Installer requested user action without a confirmation intent")
                showStatusNotification(context, status, msg, apkPath, null)
                return
            }
            confirmationIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            showStatusNotification(context, status, msg, apkPath, confirmationIntent)
            try {
                context.startActivity(confirmationIntent)
            } catch (e: Exception) {
                Log.e(TAG, "Unable to open installer confirmation; notification remains actionable", e)
            }
            return
        }

        showStatusNotification(context, status, msg, apkPath, null)
    }

    @Suppress("DEPRECATION")
    private fun pendingUserActionIntent(statusIntent: Intent): Intent? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            statusIntent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
        } else {
            statusIntent.getParcelableExtra(Intent.EXTRA_INTENT)
        }
    }

    private fun showStatusNotification(
        context: Context,
        status: Int,
        msg: String?,
        apkPath: String?,
        confirmationIntent: Intent?
    ) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "App updates", NotificationManager.IMPORTANCE_HIGH)
            )
        }
        val success = status == PackageInstaller.STATUS_SUCCESS
        val tapIntent: Intent = confirmationIntent ?: if (success) {
            context.packageManager.getLaunchIntentForPackage(context.packageName)
                ?: Intent(Intent.ACTION_MAIN)
        } else if (status == PackageInstaller.STATUS_FAILURE_CONFLICT) {
            context.packageManager.getLaunchIntentForPackage(context.packageName)
                ?: Intent(Intent.ACTION_MAIN)
        } else {
            // Tap → re-open the staged APK in the system installer (fallback).
            // This guarantees an install option ALWAYS exists post-failure.
            openApkIntent(context, apkPath)
                ?: context.packageManager.getLaunchIntentForPackage(context.packageName)
                ?: Intent(Intent.ACTION_MAIN)
        }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        else PendingIntent.FLAG_UPDATE_CURRENT
        val pi = PendingIntent.getActivity(context, 1001, tapIntent, flags)
        val note = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle(if (success) "Update installed ✅" else "Update install করতে হবে")
            .setContentText(statusMessage(status, msg))
            .setStyle(NotificationCompat.BigTextStyle().bigText(statusMessage(status, msg)))
            .setContentIntent(pi)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .build()
        nm.notify(2001, note)
    }

    private fun openApkIntent(context: Context, apkPath: String?): Intent? {
        if (apkPath.isNullOrEmpty()) return null
        return try {
            val f = File(apkPath)
            if (!f.exists()) return null
            val uri: Uri = FileProvider.getUriForFile(
                context, "${context.packageName}.fileprovider", f
            )
            Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
        } catch (e: Exception) {
            Log.e(TAG, "fallback open failed", e)
            null
        }
    }
}
