package br.com.portcall.portcall_app

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * Mantém um único FlutterEngine vivo, independente de qualquer Activity — é
 * o que permite o SipService continuar registrado/atendendo chamadas (com
 * vídeo) mesmo com o app fechado, sem precisar de um isolate separado (que
 * não consegue "transferir" uma RTCPeerConnection/MediaStream viva pra tela
 * principal — cada FlutterEngine tem seu próprio heap Dart isolado).
 * MainActivity reanexa nesse mesmo engine em vez de criar um novo — ver
 * MainActivity.provideFlutterEngine() — e PersistentEngineService o mantém
 * vivo (notificação + wakelock) enquanto o app estiver fechado.
 */
object EngineHolder {
    const val ENGINE_ID = "persistent_engine"
    private const val CHANNEL_NAME = "portcall/persistent_service"

    @Synchronized
    fun getOrCreateEngine(context: Context): FlutterEngine {
        val cache = FlutterEngineCache.getInstance()
        cache.get(ENGINE_ID)?.let { return it }

        val appContext = context.applicationContext
        val engine = FlutterEngine(appContext)
        // Registra o canal antes de rodar o main() — o lado Dart
        // (ForegroundService) pode chamar 'start' assim que terminar de
        // logar, e o handler já precisa estar pronto pra receber.
        registerServiceChannel(appContext, engine)
        engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        cache.put(ENGINE_ID, engine)
        return engine
    }

    private fun registerServiceChannel(context: Context, engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL_NAME).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val ramal = call.argument<String>("ramal")
                    PersistentEngineService.start(context, ramal)
                    result.success(null)
                }
                "stop" -> {
                    PersistentEngineService.stop(context)
                    result.success(null)
                }
                "isIgnoringBatteryOptimizations" -> {
                    val ignoring = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
                        pm.isIgnoringBatteryOptimizations(context.packageName)
                    } else {
                        true
                    }
                    result.success(ignoring)
                }
                "requestIgnoreBatteryOptimizations" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                            data = Uri.parse("package:${context.packageName}")
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        context.startActivity(intent)
                    }
                    result.success(null)
                }
                "openBatterySettings" -> {
                    // Isso aqui NÃO é o mesmo que o Doze/whitelist padrão do
                    // Android (requestIgnoreBatteryOptimizations acima) — em
                    // aparelhos Samsung existe uma camada extra de
                    // gerenciamento de bateria (One UI: Otimizado/Restrito/
                    // Sem restrições) que já vimos derrubar o registro SIP
                    // minutos depois do app acordar sozinho, mesmo já isento
                    // do Doze padrão. Não tem Intent direta e documentada pra
                    // abrir essa tela específica em todo fabricante — a tela
                    // de detalhes do app é o único caminho universal, e a
                    // opção de bateria fica a um toque dali em qualquer
                    // Android.
                    val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                        data = Uri.parse("package:${context.packageName}")
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    context.startActivity(intent)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
