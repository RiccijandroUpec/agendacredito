package com.riccijandro.agenda_credito

import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Canal "agenda/nativo" compartido por la app principal y la ventana rápida. */
object Canales {
    const val NOMBRE = "agenda/nativo"

    fun registrar(engine: FlutterEngine, ctx: Context) {
        MethodChannel(engine.dartExecutor.binaryMessenger, NOMBRE).setMethodCallHandler { llamada, r ->
            try {
                when (llamada.method) {
                    "androidId" -> r.success(Settings.Secure.getString(ctx.contentResolver, Settings.Secure.ANDROID_ID) ?: "")
                    "permisoBurbuja" -> r.success(Settings.canDrawOverlays(ctx))
                    "pedirPermisoBurbuja" -> {
                        ctx.startActivity(
                            Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:" + ctx.packageName))
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        )
                        r.success(null)
                    }
                    "burbujaActiva" -> r.success(BurbujaService.activa)
                    "mostrarBurbuja" -> {
                        Preferencias.burbuja(ctx, true)
                        ContextCompat.startForegroundService(ctx, Intent(ctx, BurbujaService::class.java))
                        r.success(null)
                    }
                    "ocultarBurbuja" -> {
                        Preferencias.burbuja(ctx, false)
                        ctx.stopService(Intent(ctx, BurbujaService::class.java))
                        r.success(null)
                    }
                    "abrirAjustesApp" -> {
                        ctx.startActivity(
                            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:" + ctx.packageName))
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        )
                        r.success(null)
                    }
                    "guardarEnDescargas" -> r.success(
                        guardarEnDescargas(ctx, llamada.argument<String>("nombre")!!, llamada.argument<ByteArray>("bytes")!!)
                    )
                    "cerrarRapido" -> {
                        RapidoActivity.actual?.finishAndRemoveTask()
                        r.success(null)
                    }
                    else -> r.notImplemented()
                }
            } catch (e: Exception) {
                r.error("nativo", e.message, null)
            }
        }
    }

    /** Descargas/AgendaCredito/<nombre>; si ya existe (creado por esta app) lo reemplaza. */
    private fun guardarEnDescargas(ctx: Context, nombre: String, bytes: ByteArray): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
        val res = ctx.contentResolver
        val coleccion = MediaStore.Downloads.EXTERNAL_CONTENT_URI
        val ruta = Environment.DIRECTORY_DOWNLOADS + "/AgendaCredito/"
        val existente = res.query(
            coleccion, arrayOf(MediaStore.MediaColumns._ID),
            MediaStore.MediaColumns.DISPLAY_NAME + "=? AND " + MediaStore.MediaColumns.RELATIVE_PATH + "=?",
            arrayOf(nombre, ruta), null
        )?.use { if (it.moveToFirst()) ContentUris.withAppendedId(coleccion, it.getLong(0)) else null }
        val uri = existente ?: res.insert(coleccion, ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, nombre)
            put(MediaStore.MediaColumns.MIME_TYPE, "application/octet-stream")
            put(MediaStore.MediaColumns.RELATIVE_PATH, ruta)
        }) ?: return false
        res.openOutputStream(uri, "wt")?.use { it.write(bytes) } ?: return false
        return true
    }
}

object Preferencias {
    private fun p(ctx: Context) = ctx.getSharedPreferences("agenda_nativo", Context.MODE_PRIVATE)
    fun burbuja(ctx: Context) = p(ctx).getBoolean("burbuja", false)
    fun burbuja(ctx: Context, si: Boolean) = p(ctx).edit().putBoolean("burbuja", si).apply()
    fun posicion(ctx: Context): Pair<Int, Int>? =
        if (p(ctx).contains("x")) Pair(p(ctx).getInt("x", 0), p(ctx).getInt("y", 0)) else null
    fun posicion(ctx: Context, x: Int, y: Int) = p(ctx).edit().putInt("x", x).putInt("y", y).apply()
}
