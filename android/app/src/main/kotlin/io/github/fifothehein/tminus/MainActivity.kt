package io.github.fifothehein.tminus

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.github.fifothehein.tminus.engine.AlarmEngineChannel
import io.github.fifothehein.tminus.engine.EngineActions
import io.github.fifothehein.tminus.engine.EngineEvents

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        AlarmEngineChannel.register(flutterEngine.dartExecutor.binaryMessenger, this)
        // Spec §9: a force stop drops every alarm, so re-arm from PlanStore whenever the app starts.
        // EngineActions also rings, or reports missed, any alert that came due while nothing ran.
        // After a crash it also shows again what was ringing or on screen when the process died.
        EngineActions.create(this).run {
            recoverPresented()
            rearmAll()
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        EngineEvents.listener = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
