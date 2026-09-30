package br.com.portcall.portcall_app

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock

/** Reagenda o PersistentEngineService pra subir de novo depois que o Android
 * mata o processo/Service sem ter sido um stop() deliberado nosso. */
class RestartReceiver : BroadcastReceiver() {
    companion object {
        private const val REQUEST_CODE = 4502

        /**
         * Intervalo do alarme de vigilância.
         *
         * Até aqui o alarme só era agendado no onDestroy()/onTaskRemoved() do
         * Service — e os dois precisam do processo vivo pra rodar. Quando o
         * Android mata o processo à força (falta de memória, gerenciador de
         * bateria da Samsung, crash), o onDestroy NÃO é chamado: nenhum alarme
         * ficava pendente e o ramal ficava fora do ar até alguém abrir o app
         * na mão. O START_STICKY deveria cobrir isso, mas é exatamente o que
         * as camadas agressivas de bateria de alguns fabricantes ignoram.
         * Medido: depois de um reload no Asterisk, três aparelhos ficaram mais
         * de 20 minutos sem voltar, enquanto o que tinha o app em primeiro
         * plano voltou em segundos.
         *
         * Com um alarme sempre pendente, o kill à força deixa de ser
         * definitivo: na próxima batida o Service sobe e registra de novo.
         *
         * 15 minutos porque é o mínimo que o Doze respeita de verdade —
         * `setAndAllowWhileIdle` só permite um disparo a cada ~9-15 min por
         * app quando o aparelho está parado, e pedir menos que isso não
         * antecipa nada, só dá a impressão de estar mais protegido.
         */
        private const val VIGILANCIA_MS = 15L * 60L * 1000L

        private fun pendingIntent(context: Context): PendingIntent {
            val intent = Intent(context, RestartReceiver::class.java)
            var flags = PendingIntent.FLAG_UPDATE_CURRENT
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                flags = flags or PendingIntent.FLAG_IMMUTABLE
            }
            return PendingIntent.getBroadcast(context, REQUEST_CODE, intent, flags)
        }

        // setAndAllowWhileIdle (não a versão "Exact") de propósito — reiniciar
        // o Service não precisa de precisão de milissegundo, e a versão exata
        // pediria a permissão SCHEDULE_EXACT_ALARM (concedida manualmente pelo
        // usuário numa tela do sistema no Android 12-13), complexidade
        // desnecessária pra esse caso.
        fun setRestartAlarm(context: Context, delayMillis: Long) {
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val triggerAt = SystemClock.elapsedRealtime() + delayMillis
            am.setAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, triggerAt, pendingIntent(context))
        }

        /** Deixa sempre um alarme pendente enquanto o Service está de pé, pra
         *  que um kill à força (sem onDestroy) não seja definitivo. */
        fun agendarVigilancia(context: Context) {
            setRestartAlarm(context, VIGILANCIA_MS)
        }

        fun cancelRestartAlarm(context: Context) {
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            am.cancel(pendingIntent(context))
        }
    }

    // Também registrado no manifest para BOOT_COMPLETED/MY_PACKAGE_REPLACED
    // (ver AndroidManifest.xml) — sem isso, reiniciar o celular ou atualizar
    // o app deixava o ramal sem registrar até alguém abrir o app na mão.
    override fun onReceive(context: Context, intent: Intent?) {
        // Reagenda ANTES de tentar subir o Service, e fora do try: se o
        // start() falhar (Android 12+ recusando serviço em primeiro plano
        // iniciado do segundo plano), o onStartCommand não roda e não seria
        // ele quem reagenda — a corrente de alarmes se quebraria aqui e o
        // ramal ficaria fora do ar de vez, que é o problema que este alarme
        // existe pra evitar.
        agendarVigilancia(context.applicationContext)
        try {
            PersistentEngineService.start(context, null)
        } catch (e: Exception) {
            android.util.Log.w(
                "PortcallRestart",
                "não consegui subir o serviço agora: ${e.message}",
            )
        }
    }
}
