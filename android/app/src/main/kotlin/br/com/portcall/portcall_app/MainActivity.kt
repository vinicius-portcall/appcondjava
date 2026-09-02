package br.com.portcall.portcall_app

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    // Reanexa no engine persistente (EngineHolder) em vez de criar um novo —
    // é o que faz o app reaparecer no estado real (registrado, em ligação
    // com vídeo etc.) mesmo depois do Android matar a Activity, ao invés de
    // reiniciar do zero pela splash screen.
    override fun provideFlutterEngine(context: Context): FlutterEngine {
        return EngineHolder.getOrCreateEngine(context)
    }
}
