package com.riccijandro.agenda_credito

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

/** Ventana transparente con el formulario rápido, encima de la app de crédito. */
class RapidoActivity : FlutterActivity() {
    companion object {
        var actual: RapidoActivity? = null
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
        actual = this
    }

    override fun getCachedEngineId(): String? =
        if (FlutterEngineCache.getInstance().contains(BurbujaService.MOTOR)) BurbujaService.MOTOR else null

    override fun getDartEntrypointFunctionName(): String = "rapidoMain"

    override fun getBackgroundMode(): BackgroundMode = BackgroundMode.transparent

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Canales.registrar(flutterEngine, applicationContext)
    }

    override fun onResume() {
        super.onResume()
        actual = this
        BurbujaService.visible(false)
        flutterEngine?.let { MethodChannel(it.dartExecutor.binaryMessenger, Canales.NOMBRE).invokeMethod("rapidoAbierto", null) }
    }

    override fun onPause() {
        super.onPause()
        BurbujaService.visible(true)
    }

    override fun onDestroy() {
        if (actual === this) actual = null
        BurbujaService.visible(true)
        super.onDestroy()
    }
}
