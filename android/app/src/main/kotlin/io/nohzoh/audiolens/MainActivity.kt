package io.nohzoh.audiolens

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(GeminiNanoPlugin())
        flutterEngine.plugins.add(LocationPlugin())
        flutterEngine.plugins.add(AudioPlayerPlugin())
    }
}
