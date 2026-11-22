package com.carriez.flutter_hbb

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.graphics.Rect
import android.os.SystemClock
import android.util.Log
import android.view.accessibility.AccessibilityNodeInfo

/**
 * Remote help that a trusted app ([RemoteControlReceiver.TRUSTED]) has just started, after the
 * person on the phone agreed to it there. Android's "start recording or casting" question
 * would follow, which an older person cannot find their way through and the helper cannot
 * see, because the screen is not shared yet. Shortly after such a start it is answered here.
 *
 * Only within [PROJECTION_MS] and only once, by the accessibility service, which must be on
 * for remote control anyway. Without a trusted start nothing changes. Connections are left
 * alone: the helper's password lets them in without a question, and one without it should
 * still be asked about.
 */
object TrustedStart {
    private const val logTag = "tagRemoteControl"
    private const val PROJECTION_MS = 60_000L

    @Volatile private var projectionUntil = 0L

    /** The trusted app has just started remote help. */
    fun arm() {
        val now = SystemClock.elapsedRealtime()
        projectionUntil = now + PROJECTION_MS
        Log.i(logTag, "trusted start: answering the screen capture question")
    }

    /**
     * Android's screen capture question, if it is up and waiting: taps its start button.
     * The question is System UI's (Samsung's too), names this app, and has the start button
     * on the right, Cancel on the left.
     */
    fun answerProjection(service: AccessibilityService) {
        if (SystemClock.elapsedRealtime() > projectionUntil) return
        val label = runCatching { service.applicationInfo.loadLabel(service.packageManager).toString() }.getOrDefault("RustDesk")
        for (window in service.windows) {
            val root = window.root ?: continue
            if (root.packageName?.toString() != "com.android.systemui") continue
            if (!mentions(root, label)) continue
            val button = startButton(root)
            Log.d(logTag, "trusted start: capture question found, button ${button?.text ?: button?.viewIdResourceName}")
            if (button == null) continue
            if (click(service, button)) {
                projectionUntil = 0L
                Log.i(logTag, "trusted start: agreed to screen capture")
                return
            }
        }
    }

    private fun nodes(root: AccessibilityNodeInfo): Sequence<AccessibilityNodeInfo> = sequence {
        val queue = ArrayDeque(listOf(root))
        while (queue.isNotEmpty()) {
            val n = queue.removeFirst()
            yield(n)
            for (i in 0 until n.childCount) n.getChild(i)?.let { queue.add(it) }
        }
    }

    private fun mentions(root: AccessibilityNodeInfo, label: String) =
        nodes(root).any { it.text?.contains(label, ignoreCase = true) == true }

    /** By its id where System UI keeps AOSP's, else the rightmost button. */
    private fun startButton(root: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        for (id in listOf("com.android.systemui:id/button_start", "android:id/button1")) {
            root.findAccessibilityNodeInfosByViewId(id).firstOrNull { it.isEnabled && it.isVisibleToUser }?.let { return it }
        }
        // Samsung draws its own dialog, its buttons not always as Buttons (a clickable layout
        // around a label, say): anything clickable.
        val buttons = nodes(root).filter { it.isClickable && it.isEnabled && it.isVisibleToUser }.toList()
        if (buttons.size < 2) return null
        // Cancel and start share a row; a spinner or other control above them is not one of them.
        val bounds = buttons.associateWith { Rect().also { r -> it.getBoundsInScreen(r) } }
        val row = bounds.values.maxOf { it.centerY() }
        return bounds.filter { kotlin.math.abs(it.value.centerY() - row) < it.value.height() }
            .maxByOrNull { it.value.centerX() }?.key
    }

    private fun click(service: AccessibilityService, node: AccessibilityNodeInfo): Boolean {
        if (node.performAction(AccessibilityNodeInfo.ACTION_CLICK)) return true
        // Some dialogs only take touches: a tap in the middle of the button.
        val r = Rect().also { node.getBoundsInScreen(it) }
        val path = Path().apply { moveTo(r.exactCenterX(), r.exactCenterY()) }
        return service.dispatchGesture(
            GestureDescription.Builder().addStroke(GestureDescription.StrokeDescription(path, 0, 50)).build(), null, null,
        )
    }
}
