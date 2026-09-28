package br.com.portcall.portcall_app

import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.media.ToneGenerator
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
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

    /** Volume do tom de chamada, 0..100. Baixo de propósito: o tom serve
     *  pra dizer "está chamando", não pra competir com a voz. */
    private const val RINGBACK_VOLUME = 60

    /** Quantas vezes insistir no tom quando o canal de voz recusa, e de
     *  quanto em quanto tempo. Quatro tentativas a 600ms cobrem ~2s, tempo
     *  de sobra pro WebRTC terminar de montar a sessão de áudio. */
    private const val RINGBACK_MAX_TENTATIVAS = 4
    private const val RINGBACK_RETRY_MS = 600L
    private const val TAG_RINGBACK = "PortcallRingback"

    private var ringback: ToneGenerator? = null

    /** A ligação ainda está chamando (ou seja: o tom DEVERIA estar saindo). */
    private var ringbackAtivo = false

    /** O tom de fato começou a sair — evita reiniciar o tom no meio. */
    private var ringbackTocando = false
    private var ringbackTentativas = 0
    private val ringbackHandler = Handler(Looper.getMainLooper())
    private val ringbackRetry = Runnable { tentarRingback() }

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
                // Tom de chamada (ringback) de quem liga, enquanto o outro
                // lado toca. Não vem do servidor: o Asterisk responde
                // "180 Ringing" sem áudio (não manda 183 com early media),
                // que é o comportamento normal do SIP — quem gera o tom é o
                // aparelho de quem ligou. Sem isso a ligação fica muda até
                // alguém atender, e parece que não completou.
                //
                // ToneGenerator em vez de tocar um arquivo: é o tom padrão
                // do próprio Android, não precisa de asset nem de pacote de
                // áudio novo, e sai pelo canal de voz — então respeita o
                // viva-voz/fone já escolhido pra chamada.
                "startRingback" -> result.success(iniciarRingback())
                "stopRingback" -> {
                    pararRingback()
                    result.success(true)
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

    /**
     * Liga o tom de chamada, insistindo se o canal de voz recusar.
     *
     * O `startTone` DEVOLVE se conseguiu tocar, e esse retorno ser ignorado
     * era o que fazia o tom falhar de vez em quando: quando a ligação acabou
     * de sair, o WebRTC ainda está montando a sessão de áudio e o
     * STREAM_VOICE_CALL pode estar ocupado por um instante — aí o tom
     * simplesmente não saía e ninguém ficava sabendo. Um ToneGenerator que
     * recusou uma vez não volta a aceitar, então a retentativa descarta o
     * objeto e cria outro.
     */
    @Synchronized
    private fun iniciarRingback(): Boolean {
        // Já tocando: não reinicia. O lado Dart chama tanto quando a ligação
        // sai quanto quando o outro lado começa a tocar (duas chamadas pra
        // mesma ligação, de propósito — ver SipService.callStateChanged), e
        // um segundo startTone cortaria o tom no meio.
        if (ringbackTocando) return true
        ringbackAtivo = true
        ringbackTentativas = 0
        return tentarRingback()
    }

    @Synchronized
    private fun tentarRingback(): Boolean {
        if (!ringbackAtivo || ringbackTocando) return ringbackTocando
        ringbackTentativas++

        val tocou = try {
            val gerador = ringback ?: ToneGenerator(
                AudioManager.STREAM_VOICE_CALL,
                RINGBACK_VOLUME,
            ).also { ringback = it }
            gerador.startTone(ToneGenerator.TONE_SUP_RINGTONE)
        } catch (e: Exception) {
            Log.w(TAG_RINGBACK, "ToneGenerator indisponível: ${e.message}")
            false
        }

        if (tocou) {
            ringbackTocando = true
            return true
        }

        liberarRingback()
        if (ringbackTentativas < RINGBACK_MAX_TENTATIVAS) {
            Log.w(TAG_RINGBACK, "canal de voz recusou o tom (tentativa $ringbackTentativas); repetindo")
            ringbackHandler.postDelayed(ringbackRetry, RINGBACK_RETRY_MS)
        } else {
            Log.w(TAG_RINGBACK, "desistindo do tom após $ringbackTentativas tentativas")
        }
        return false
    }

    @Synchronized
    private fun pararRingback() {
        ringbackAtivo = false
        ringbackTocando = false
        ringbackHandler.removeCallbacks(ringbackRetry)
        try {
            ringback?.stopTone()
        } catch (_: Exception) {
            // Já liberado/nunca criado — nada a fazer.
        }
        liberarRingback()
    }

    private fun liberarRingback() {
        try {
            ringback?.release()
        } catch (_: Exception) {
        }
        ringback = null
    }
}
