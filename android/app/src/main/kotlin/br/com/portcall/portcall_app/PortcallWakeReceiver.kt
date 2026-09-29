package br.com.portcall.portcall_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Acorda o app quando o servidor avisa que uma chamada está chegando.
 *
 * O `portcall_router.agi` manda um push de dados (`tipo=chamada`) antes de
 * discar pro ramal, pra que o app volte a registrar no Asterisk caso o
 * Android já tenha matado o processo. Esse push existia e era entregue — o
 * Firebase respondia httpCode=200 — mas **nunca acordava nada**, e o motivo
 * estava aqui no lado Android:
 *
 * O handler Dart (`_firebaseMessagingBackgroundHandler`, em main.dart) roda
 * num isolate separado, criado pelo plugin do Firebase. Esse isolate tem o
 * próprio FlutterEngine, e o canal `portcall/persistent_service` é registrado
 * só no engine persistente (ver EngineHolder.getOrCreateEngine). Resultado:
 * `ForegroundService.start()` lançava MissingPluginException lá dentro, o
 * `catch (_)` do handler engolia o erro, e não sobrava rastro em lugar
 * nenhum — nem no celular nem no servidor. Confirmado em teste: ramal sem
 * registro + push entregue = 30 segundos depois, ainda sem registro.
 *
 * Por isso este receiver é NATIVO e não fala com o Dart: ele inicia o
 * PersistentEngineService direto, e é o `onCreate` dele que sobe o engine e
 * dispara o registro SIP. Sem canal, sem isolate, sem nada pra dar errado no
 * meio.
 *
 * Por que um BroadcastReceiver e não um FirebaseMessagingService: quem recebe
 * a mensagem neste app é o `FlutterFirebaseMessagingReceiver` do plugin, um
 * BroadcastReceiver — o serviço de MESSAGING_EVENT não chega a ser acionado
 * no caminho de segundo plano. Dois receivers para
 * `com.google.android.c2dm.intent.RECEIVE` já convivem aqui (o do SDK do
 * Firebase e o do plugin), então este é o terceiro, e nenhum deles interrompe
 * o broadcast dos outros.
 */
class PortcallWakeReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        // Nos pushes de dados, as chaves do payload chegam como extras
        // diretos (é assim que o próprio plugin monta o RemoteMessage).
        val extras = intent.extras ?: return
        if (extras.getString("tipo") != TIPO_CHAMADA) return

        try {
            PersistentEngineService.start(
                context.applicationContext,
                extras.getString("ramal"),
            )
            Log.i(TAG, "push de chamada recebido: subindo o serviço para registrar")
        } catch (e: Exception) {
            // Android 12+ barra iniciar serviço em primeiro plano a partir do
            // segundo plano, exceto na isenção temporária que uma mensagem de
            // alta prioridade concede (o servidor manda priority=high, ver
            // fcm_enviar_dados no fcm_helper.php). Se ainda assim for
            // recusado, a chamada continua caindo pro celular da rota — não
            // pode derrubar o processo por causa disso.
            Log.w(TAG, "push de chamada: não consegui subir o serviço: ${e.message}")
        }
    }

    private companion object {
        const val TAG = "PortcallWake"
        const val TIPO_CHAMADA = "chamada"
    }
}
