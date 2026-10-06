package io.github.fifothehein.tminus

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.github.fifothehein.tminus.engine.AlarmEngineChannel
import io.github.fifothehein.tminus.engine.AlarmScheduler
import io.github.fifothehein.tminus.engine.EngineEvents

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        AlarmEngineChannel.register(flutterEngine.dartExecutor.binaryMessenger, this)
        // Spec §9: a force stop drops every alarm, so re-arm from PlanStore whenever the app starts.
        AlarmScheduler(this).rearmAll()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        EngineEvents.listener = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
