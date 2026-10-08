package io.github.fifothehein.tminus

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.github.fifothehein.tminus.engine.AlarmEngineChannel
import io.github.fifothehein.tminus.engine.AlarmScreenRoute
import io.github.fifothehein.tminus.engine.EngineActions

class MainActivity : FlutterActivity() {
    private var engineChannel: AlarmEngineChannel? = null

    init {
        // Opening the app (launcher or recents) while an alarm rings goes to the alarm screen.
        lifecycle.addObserver(AlarmScreenRoute(this))
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        engineChannel = AlarmEngineChannel.register(flutterEngine.dartExecutor.binaryMessenger, this)
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
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
