package br.com.portcall.portcall_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/**
 * Substitui o antigo ForegroundService do pacote flutter_foreground_task —
 * em vez de rodar um isolate/engine separado, esse Service só mantém vivo
 * (notificação + wakelock) o MESMO FlutterEngine que a MainActivity usa
 * (ver EngineHolder). Não tem nenhuma lógica de SIP aqui — isso continua
 * inteiramente no SipService (lib/services/sip_service.dart), que roda
 * dentro do engine independente de Activity estar anexada ou não.
 */
class PersistentEngineService : Service() {
    companion object {
        private const val CHANNEL_ID = "portcall_sip_channel"
        private const val CHANNEL_NAME = "Conexão SIP"
        private const val NOTIFICATION_ID = 4501
        private const val EXTRA_RAMAL = "ramal"

        private var stoppingDeliberadamente = false
        private var lastRamal: String? = null

        fun start(context: Context, ramal: String?) {
            stoppingDeliberadamente = false
            if (ramal != null) lastRamal = ramal
            val intent = Intent(context, PersistentEngineService::class.java).apply {
                putExtra(EXTRA_RAMAL, ramal ?: lastRamal)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            stoppingDeliberadamente = true
            RestartReceiver.cancelRestartAlarm(context)
            context.stopService(Intent(context, PersistentEngineService::class.java))
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onCreate() {
        super.onCreate()
        // Idempotente — não recria se a MainActivity (ou um restart
        // anterior) já tiver criado o engine.
        EngineHolder.getOrCreateEngine(applicationContext)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        EngineHolder.getOrCreateEngine(applicationContext)
        val ramal = intent?.getStringExtra(EXTRA_RAMAL) ?: lastRamal
        startForegroundNotification(ramal)
        acquireWakeLock()
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        super.onDestroy()
        releaseWakeLock()
        // Só reagenda restart se não foi um stop() deliberado (logout) — o
        // Android matando o Service por conta própria (memória/bateria) não
        // pode deixar o ramal sem registro sem ninguém perceber.
        if (!stoppingDeliberadamente) {
            RestartReceiver.setRestartAlarm(applicationContext, 3000)
        }
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        // App removido dos recentes — o Service já é pra continuar rodando,
        // mas alguns fabricantes (Samsung/Xiaomi) matam o processo aqui
        // mesmo assim; reforça com um alarme de segurança.
        RestartReceiver.setRestartAlarm(applicationContext, 1000)
    }

    private fun startForegroundNotification(ramal: String?) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(NotificationManager::class.java)
            if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    CHANNEL_NAME,
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = "Mantém o ramal registrado em segundo plano."
                }
                nm.createNotificationChannel(channel)
            }
        }

        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        var piFlags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            piFlags = piFlags or PendingIntent.FLAG_IMMUTABLE
        }
        val contentIntent = PendingIntent.getActivity(this, 0, launchIntent, piFlags)

        val text = if (ramal != null) "Ramal $ramal — online" else "Mantendo o registro ativo"

        val notification: Notification = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
                .setOngoing(true)
                .setSmallIcon(applicationInfo.icon)
                .setContentTitle("Portcall conectado")
                .setContentText(text)
                .setContentIntent(contentIntent)
                .build()
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
                .setOngoing(true)
                .setSmallIcon(applicationInfo.icon)
                .setContentTitle("Portcall conectado")
                .setContentText(text)
                .setContentIntent(contentIntent)
                .build()
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    @Suppress("DEPRECATION")
    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "PersistentEngineService:WakeLock").apply {
            setReferenceCounted(false)
            acquire()
        }
    }

    private fun releaseWakeLock() {
        wakeLock?.let {
            if (it.isHeld) it.release()
        }
        wakeLock = null
    }
}
