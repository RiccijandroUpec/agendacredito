package com.riccijandro.agenda_credito

import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.content.res.Configuration
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.widget.ImageView
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import kotlin.math.abs

/**
 * Burbuja flotante sobre las demás apps. Al tocarla abre [RapidoActivity] encima de la app de
 * crédito. Deja precalentado el motor de Flutter de la ventana rápida para que abra al instante.
 */
class BurbujaService : Service() {
    companion object {
        const val MOTOR = "rapido"
        private const val CANAL = "burbuja"
        private const val ACCION_OCULTAR = "ocultar"
        @Volatile var activa = false
        private var instancia: BurbujaService? = null

        /** La ventana rápida oculta la burbuja mientras está abierta. */
        fun visible(si: Boolean) {
            instancia?.vista?.visibility = if (si) View.VISIBLE else View.GONE
        }
    }

    private lateinit var wm: WindowManager
    private var vista: ImageView? = null
    private lateinit var params: WindowManager.LayoutParams
    private var tam = 0

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        wm = getSystemService(WINDOW_SERVICE) as WindowManager
        instancia = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        primerPlano()
        if (intent?.action == ACCION_OCULTAR || !Settings.canDrawOverlays(this)) {
            if (intent?.action == ACCION_OCULTAR) Preferencias.burbuja(this, false)
            stopSelf()
            return START_NOT_STICKY
        }
        if (vista == null) mostrar()
        precalentar()
        activa = true
        return START_STICKY
    }

    private fun primerPlano() {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(CANAL, "Burbuja", NotificationManager.IMPORTANCE_MIN).apply {
                    description = "Aviso fijo mientras la burbuja está activa"
                    setShowBadge(false)
                }
            )
        }
        val pi = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val abrir = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), pi)
        val ocultar = PendingIntent.getService(
            this, 1, Intent(this, BurbujaService::class.java).setAction(ACCION_OCULTAR), pi
        )
        val n = NotificationCompat.Builder(this, CANAL)
            .setSmallIcon(R.drawable.ic_burbuja)
            .setContentTitle("Burbuja de la Agenda activa")
            .setContentText("Tócala para anotar un cliente mientras revisas el crédito")
            .setContentIntent(abrir)
            .addAction(0, "Ocultar burbuja", ocultar)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .build()
        ServiceCompat.startForeground(
            this, 7, n,
            if (Build.VERSION.SDK_INT >= 34) ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE else 0
        )
    }

    private fun tipoVentana() =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE

    @SuppressLint("ClickableViewAccessibility")
    private fun mostrar() {
        val d = resources.displayMetrics.density
        tam = (60 * d).toInt()
        val relleno = (15 * d).toInt()
        val img = ImageView(this).apply {
            setImageResource(R.drawable.ic_burbuja)
            setBackgroundResource(R.drawable.burbuja_fondo)
            setPadding(relleno, relleno, relleno, relleno)
            elevation = 8 * d
            contentDescription = "Anotar cliente"
        }
        val (px, py) = Preferencias.posicion(this) ?: Pair(resources.displayMetrics.widthPixels - tam, (160 * d).toInt())
        params = WindowManager.LayoutParams(
            tam, tam, tipoVentana(),
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = px
            y = py
        }
        val umbral = ViewConfiguration.get(this).scaledTouchSlop
        var x0 = 0
        var y0 = 0
        var tx = 0f
        var ty = 0f
        var movio = false
        img.setOnTouchListener { v, e ->
            when (e.action) {
                MotionEvent.ACTION_DOWN -> {
                    x0 = params.x; y0 = params.y; tx = e.rawX; ty = e.rawY; movio = false
                    v.animate().scaleX(0.9f).scaleY(0.9f).setDuration(80).start()
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = e.rawX - tx
                    val dy = e.rawY - ty
                    if (!movio && (abs(dx) > umbral || abs(dy) > umbral)) movio = true
                    if (movio) {
                        params.x = x0 + dx.toInt()
                        params.y = y0 + dy.toInt()
                        wm.updateViewLayout(v, params)
                    }
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    v.animate().scaleX(1f).scaleY(1f).setDuration(80).start()
                    if (!movio && e.action == MotionEvent.ACTION_UP) abrirFormulario() else pegarAlBorde()
                }
            }
            true
        }
        wm.addView(img, params)
        vista = img
        pegarAlBorde()
    }

    private fun pegarAlBorde() {
        val v = vista ?: return
        val m = resources.displayMetrics
        params.x = if (params.x + tam / 2 < m.widthPixels / 2) 0 else m.widthPixels - tam
        params.y = params.y.coerceIn(0, (m.heightPixels - tam * 2).coerceAtLeast(0))
        wm.updateViewLayout(v, params)
        Preferencias.posicion(this, params.x, params.y)
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        pegarAlBorde()
    }

    private fun abrirFormulario() {
        startActivity(
            Intent(this, RapidoActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_ANIMATION)
        )
    }

    private fun precalentar() {
        if (FlutterEngineCache.getInstance().contains(MOTOR)) return
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(applicationContext)
        loader.ensureInitializationComplete(applicationContext, null)
        val motor = FlutterEngine(applicationContext)
        Canales.registrar(motor, applicationContext)
        motor.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "rapidoMain"))
        FlutterEngineCache.getInstance().put(MOTOR, motor)
    }

    override fun onDestroy() {
        activa = false
        vista?.let { runCatching { wm.removeView(it) } }
        vista = null
        if (RapidoActivity.actual == null) {
            FlutterEngineCache.getInstance().get(MOTOR)?.destroy()
            FlutterEngineCache.getInstance().remove(MOTOR)
        }
        if (instancia === this) instancia = null
        super.onDestroy()
    }
}
