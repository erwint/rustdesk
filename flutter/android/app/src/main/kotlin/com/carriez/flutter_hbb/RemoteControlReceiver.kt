package com.carriez.flutter_hbb

import android.Manifest.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
import android.Manifest.permission.SYSTEM_ALERT_WINDOW
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import com.hjq.permissions.XXPermissions

/** Starts the screen sharing service: the service goes online and Android asks to share the screen. */
const val ACT_REMOTE_START = "com.carriez.flutter_hbb.action.START_SERVICE"
/** Stops the service as its own stop button does: capture ends and the device goes offline. */
const val ACT_REMOTE_STOP = "com.carriez.flutter_hbb.action.STOP_SERVICE"

/**
 * Start and stop on demand, for a trusted app that offers remote help (a launcher for an
 * older person, say), so the service need not run all the time or start on every boot.
 *
 * Only the apps in [TRUSTED] may use it. Android 14 and newer name the sender of a broadcast
 * when it agrees to (BroadcastOptions.setShareIdentityEnabled); older versions do not, and
 * there the receiver does nothing. Like the start-on-boot path it needs "display over other
 * apps" and no battery optimisation, which let the service start from the background.
 */
class RemoteControlReceiver : BroadcastReceiver() {
    private val logTag = "tagRemoteControl"

    override fun onReceive(context: Context, intent: Intent) {
        val sender = if (Build.VERSION.SDK_INT >= 34) sentFromPackage else null
        if (sender == null || sender !in TRUSTED) {
            Log.w(logTag, "ignored ${intent.action} from ${sender ?: "an unnamed sender"}")
            return
        }
        when (intent.action) {
            ACT_REMOTE_START -> {
                if (!XXPermissions.isGranted(context, REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, SYSTEM_ALERT_WINDOW)) {
                    Log.w(logTag, "REQUEST_IGNORE_BATTERY_OPTIMIZATIONS or SYSTEM_ALERT_WINDOW is not granted")
                    return
                }
                val it = Intent(context, MainService::class.java).apply {
                    action = ACT_INIT_MEDIA_PROJECTION_AND_SERVICE
                    // The same as after a boot: go online, then ask for the screen.
                    putExtra(EXT_INIT_FROM_BOOT, true)
                }
                runCatching {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(it)
                    else context.startService(it)
                }.onFailure { Log.w(logTag, "start failed: $it") }
            }
            ACT_REMOTE_STOP -> runCatching {
                context.startService(Intent(context, MainService::class.java).setAction(ACT_STOP_SERVICE))
            }.onFailure { Log.w(logTag, "stop failed (not running?): $it") }
        }
    }

    companion object {
        val TRUSTED = setOf("com.ryowave.varelo")
    }
}
