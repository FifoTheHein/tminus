package io.github.fifothehein.tminus

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs
import io.flutter.embedding.engine.FlutterEngine
import io.github.fifothehein.tminus.engine.AlarmEngineChannel
import io.github.fifothehein.tminus.engine.AlarmScreenRoute
import io.github.fifothehein.tminus.engine.EngineActions
import io.github.fifothehein.tminus.sync.PreSyncScheduler
import io.github.fifothehein.tminus.sync.SyncChannel
import io.github.fifothehein.tminus.sync.SyncScheduler
import io.github.fifothehein.tminus.ui.RouteExtra
import io.github.fifothehein.tminus.ui.UiChannel

class MainActivity : FlutterActivity() {
    private var engineChannel: AlarmEngineChannel? = null
    private var syncChannel: SyncChannel? = null
    private var uiChannel: UiChannel? = null

    init {
        // Opening the app (launcher or recents) while an alarm rings goes to the alarm screen.
        lifecycle.addObserver(AlarmScreenRoute(this))
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        engineChannel = AlarmEngineChannel.register(flutterEngine.dartExecutor.binaryMessenger, this)
        syncChannel = SyncChannel.register(flutterEngine.dartExecutor.binaryMessenger, this)
        uiChannel = UiChannel.register(flutterEngine.dartExecutor.binaryMessenger, this)
        SyncScheduler(this).ensurePeriodic() // spec §7: every 15 min with a network
        PreSyncScheduler(this).armNext() // a force stop drops this alarm too
        // Spec §9: a force stop drops every alarm, so re-arm from PlanStore whenever the app starts.
        // EngineActions also rings, or reports missed, any alert that came due while nothing ran.
        // After a crash it also shows again what was ringing or on screen when the process died.
        EngineActions.create(this).run {
            recoverPresented()
            rearmAll()
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        engineChannel?.detach() // only this engine's live events; a headless engine keeps its own
        engineChannel = null
        syncChannel?.detach() // releases a sync lock the UI isolate still held
        syncChannel = null
        uiChannel?.detach() // answers a waiting picker or permission request
        uiChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    /**
     * Only the Fix route, and only in its one shape (Plan 5 decision 10). Never Flutter's own `route`
     * extra or an intent's data path: MainActivity is exported, so either would let any app open any
     * screen.
     */
    override fun getInitialRoute(): String = RouteExtra.from(intent) ?: "/"

    override fun shouldHandleDeeplinking(): Boolean = false

    // The same goes for the other launch extras FlutterActivity reads. Left alone, another app could start
    // the UI engine at `syncMain` (a fetching sync with no UI), crash start-up (an entrypoint-args extra
    // that is not a list, an unknown cached engine id, a bad background mode) or keep the engine alive
    // after the screen closes. The UI engine always runs `main`, is built here, is opaque and goes with
    // the activity. The shell-args and app-bundle-path methods stay as they are: `flutter run` passes its
    // debug settings through them.
    override fun getDartEntrypointFunctionName(): String = "main"

    override fun getDartEntrypointArgs(): List<String>? = null

    override fun getCachedEngineId(): String? = null

    override fun getCachedEngineGroupId(): String? = null

    override fun getBackgroundMode(): FlutterActivityLaunchConfigs.BackgroundMode =
        FlutterActivityLaunchConfigs.BackgroundMode.opaque

    override fun shouldDestroyEngineWithHost(): Boolean = true

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        RouteExtra.from(intent)?.let { flutterEngine?.navigationChannel?.pushRouteInformation(it) }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (uiChannel?.onActivityResult(requestCode, resultCode, data) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<String>, grantResults: IntArray) {
        if (uiChannel?.onRequestPermissionsResult(requestCode, grantResults) == true) return
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }
}
