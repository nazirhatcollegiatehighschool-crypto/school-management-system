package com.school.teacher_app

import android.app.Activity
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.OutputStream

/// Professional in-app updater channel: "school.updater".
///
/// Scientific fix for the reported loop ("100% → unknown-source → back →
/// no install option → repeat"):
///
/// OLD PATH (broken): OpenFilex.open(apk) → ACTION_VIEW + FileProvider URI →
///   system package-installer UI (a SEPARATE app surface).
///   Failure modes observed on this device family:
///   1. The installer UI opens WITHOUT the "Install" button when the apk
///      sits in getExternalStorageDirectory (scoped-storage / ownership).
///   2. Back-press DESTROYS the installer activity — the Dart side already
///      popped its progress dialog, so the user lands on a dead screen with
///      no retry. Re-tapping restarts the whole download.
///   3. REQUEST_INSTALL_PACKAGES denied → installer shows "unknown source"
///      instead of an install button.
///
/// NEW PATH (PackageInstaller.Session API — same API the Play Store uses):
///   1. Stream the APK into a staged install session (no external viewer).
///   2. commit() → system shows ONE inline confirmation ("Do you want to
///      install/update this app?") with Install + Cancel INSIDE the dialog.
///   3. Status receiver reports SUCCESS / FAILURE back to Dart, which keeps
///      a persistent "Install Update" card until success — back-press can
///      never strand the user.
///
/// Same package name + same signature + higher versionCode ⇒ UPDATE
/// (data preserved). Anything else ⇒ precise error code, not a loop.
class MainActivity : FlutterActivity() {
    private val CHANNEL = "school.updater"
    private val TAG = "SchoolUpdater"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canRequestInstalls" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            result.success(packageManager.canRequestPackageInstalls())
                        } else {
                            result.success(true)
                        }
                    }
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrEmpty()) {
                            result.error("NO_PATH", "APK path missing", null)
                        } else {
                            installApk(File(path), result)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun installApk(apkFile: File, result: MethodChannel.Result) {
        if (!apkFile.exists() || apkFile.length() < 5 * 1024 * 1024) {
            result.error("BAD_FILE", "APK file missing or too small (${apkFile.length()} bytes)", null)
            return
        }
        try {
            val candidate = packageManager.getPackageArchiveInfo(apkFile.absolutePath, 0)
            if (candidate == null) {
                result.error("INVALID_APK", "Downloaded file is not a valid Android package", null)
                return
            }
            if (candidate.packageName != packageName) {
                result.error("PACKAGE_MISMATCH", "This update belongs to ${candidate.packageName}", null)
                return
            }
            val installed = packageManager.getPackageInfo(packageName, 0)
            val candidateVersion = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                candidate.longVersionCode
            } else {
                @Suppress("DEPRECATION")
                candidate.versionCode.toLong()
            }
            val installedVersion = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                installed.longVersionCode
            } else {
                @Suppress("DEPRECATION")
                installed.versionCode.toLong()
            }
            if (candidateVersion <= installedVersion) {
                result.error("VERSION_NOT_NEWER", "Downloaded version is not newer than the installed app", null)
                return
            }

            val installer = packageManager.packageInstaller
            val params = PackageInstaller.SessionParams(
                PackageInstaller.SessionParams.MODE_FULL_INSTALL
            )
            params.setAppPackageName(packageName)
            params.setSize(apkFile.length())
            // App-private dir read: installer reads via our stream, URI perms unneeded.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                params.setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_REQUIRED)
            }
            val sessionId = installer.createSession(params)
            val session = installer.openSession(sessionId)
            try {
                FileInputStream(apkFile).use { input ->
                    session.openWrite("app", 0, apkFile.length()).use { out: OutputStream ->
                        input.copyTo(out)
                        session.fsync(out)
                    }
                }
                // Status callback → back to Dart (and a system notification on failure).
                val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
                else PendingIntent.FLAG_UPDATE_CURRENT
                val intent = Intent(this, InstallStatusReceiver::class.java).apply {
                    action = InstallStatusReceiver.ACTION_STATUS
                    putExtra("sessionId", sessionId)
                    putExtra("apkPath", apkFile.absolutePath)
                }
                val pi = PendingIntent.getBroadcast(this, sessionId, intent, flags)
                session.commit(pi.intentSender)
                session.close()
                Log.i(TAG, "session $sessionId committed for ${apkFile.name}")
                result.success(sessionId)
            } catch (e: Exception) {
                try { session.abandon() } catch (_: Exception) {}
                try { session.close() } catch (_: Exception) {}
                Log.e(TAG, "session failed", e)
                result.error("SESSION_FAILED", e.message, null)
            }
        } catch (e: SecurityException) {
            // REQUEST_INSTALL_PACKAGES denied at OS level → Dart opens Settings.
            Log.e(TAG, "install permission denied", e)
            result.error("PERMISSION_DENIED", "Unknown-sources permission not granted", null)
        } catch (e: Exception) {
            Log.e(TAG, "install failed", e)
            result.error("INSTALL_FAILED", e.message, null)
        }
    }

    // Kept for diagnostics: open via viewer as a LAST resort only.
    @Suppress("unused")
    private fun openViaViewer(apkFile: File): Boolean {
        return try {
            val uri: Uri = FileProvider.getUriForFile(
                this, "$packageName.fileprovider", apkFile
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(intent)
            true
        } catch (e: Exception) {
            Log.e(TAG, "viewer open failed", e)
            false
        }
    }
}
