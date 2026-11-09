package com.riccijandro.agenda_credito

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Settings
import androidx.core.content.ContextCompat

/** Vuelve a mostrar la burbuja al encender la tablet o al actualizar la app, si estaba activa. */
class ArranqueReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED && intent.action != Intent.ACTION_MY_PACKAGE_REPLACED) return
        if (!Preferencias.burbuja(ctx) || !Settings.canDrawOverlays(ctx)) return
        runCatching { ContextCompat.startForegroundService(ctx, Intent(ctx, BurbujaService::class.java)) }
    }
}
