package com.carriez.flutter_hbb

import android.app.Activity
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.util.Log

/**
 * Starts the screen sharing service for a trusted app, from the foreground.
 *
 * A broadcast ([RemoteControlReceiver]) reaches RustDesk in the background, where Android
 * only lets it start a service and ask to share the screen with "display over other apps"
 * and no battery optimisation, and installs from a browser hide the former behind
 * "restricted settings". The trusted app is on screen when the person agrees to remote help,
 * so it opens this invisible screen instead: a visible activity may start the service, which
 * then asks to share the screen, without either permission. It closes itself after a moment.
 *
 * Only [RemoteControlReceiver.TRUSTED] apps: Android 14 and newer name the app that started
 * an activity when it agrees to (ActivityOptions.setShareIdentityEnabled).
 */
class RemoteStartActivity : Activity() {
    private val logTag = "tagRemoteControl"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val caller = if (Build.VERSION.SDK_INT >= 34) launchedFromPackage else null
        if (caller == null || caller !in RemoteControlReceiver.TRUSTED) {
            Log.w(logTag, "ignored start from ${caller ?: "an unnamed app"}")
            finish()
            return
        }
        TrustedStart.arm()
        val it = Intent(this, MainService::class.java).apply {
            action = ACT_INIT_MEDIA_PROJECTION_AND_SERVICE
            // The same as after a boot: go online, then ask for the screen.
            putExtra(EXT_INIT_FROM_BOOT, true)
        }
        runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(it) else startService(it)
        }.onFailure { Log.w(logTag, "start failed: $it") }
        // The service asks to share the screen from here; staying a moment keeps RustDesk in
        // the foreground until that question is up.
        android.os.Handler(mainLooper).postDelayed({ finish() }, 2_000)
    }
}
