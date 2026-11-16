package com.anymyst.anymyst_plan

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val canal = "anymyst/archivos"
    private val pedirGuardar = 4101
    private val pedirAbrir = 4102
    private var pendiente: MethodChannel.Result? = null
    private var bytesPendientes: ByteArray? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, canal).setMethodCallHandler { call, result ->
            when (call.method) {
                "carpetaDatos" -> result.success(filesDir.absolutePath)
                "guardar" -> {
                    if (pendiente != null) {
                        result.error("ocupado", "Ya hay una operación en curso", null)
                    } else {
                        bytesPendientes = call.argument<ByteArray>("bytes")
                        pendiente = result
                        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = call.argument<String>("mime") ?: "application/octet-stream"
                            putExtra(Intent.EXTRA_TITLE, call.argument<String>("nombre") ?: "plan")
                        }
                        startActivityForResult(intent, pedirGuardar)
                    }
                }
                "abrir" -> {
                    if (pendiente != null) {
                        result.error("ocupado", "Ya hay una operación en curso", null)
                    } else {
                        pendiente = result
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "*/*"
                        }
                        startActivityForResult(intent, pedirAbrir)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != pedirGuardar && requestCode != pedirAbrir) return
        val res = pendiente ?: return
        pendiente = null
        val uri: Uri? = data?.data
        try {
            if (resultCode != Activity.RESULT_OK || uri == null) {
                if (requestCode == pedirGuardar) res.success(false) else res.success(null)
            } else if (requestCode == pedirGuardar) {
                contentResolver.openOutputStream(uri, "wt")?.use { it.write(bytesPendientes ?: ByteArray(0)) }
                res.success(true)
            } else {
                var nombre = "archivo"
                contentResolver.query(uri, null, null, null, null)?.use { c ->
                    val i = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (i >= 0 && c.moveToFirst()) nombre = c.getString(i)
                }
                val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() } ?: ByteArray(0)
                res.success(mapOf("nombre" to nombre, "bytes" to bytes))
            }
        } catch (e: Exception) {
            res.error("error", e.message, null)
        }
        bytesPendientes = null
    }
}
