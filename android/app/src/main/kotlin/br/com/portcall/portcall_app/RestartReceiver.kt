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

        fun cancelRestartAlarm(context: Context) {
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            am.cancel(pendingIntent(context))
        }
    }

    // Também registrado no manifest para BOOT_COMPLETED/MY_PACKAGE_REPLACED
    // (ver AndroidManifest.xml) — sem isso, reiniciar o celular ou atualizar
    // o app deixava o ramal sem registrar até alguém abrir o app na mão.
    override fun onReceive(context: Context, intent: Intent?) {
        PersistentEngineService.start(context, null)
    }
}
