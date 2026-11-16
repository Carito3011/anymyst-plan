package com.anymyst.anymyst_plan

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
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
    private val pedirCarpeta = 4104
    private var recibido: Map<String, Any>? = null
    private var canalArchivos: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val canalA = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, canal)
        canalArchivos = canalA
        leerIntent(intent, false)
        canalA.setMethodCallHandler { call, result ->
            when (call.method) {
                "archivoRecibido" -> {
                    result.success(recibido)
                    recibido = null
                }
                "elegirCarpeta" -> {
                    if (pendiente != null) {
                        result.error("ocupado", "Ya hay una operación en curso", null)
                    } else {
                        pendiente = result
                        startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE), pedirCarpeta)
                    }
                }
                "listarCarpeta", "leerDeCarpeta", "escribirEnCarpeta" -> {
                    val arbol = call.argument<String>("carpeta") ?: ""
                    val nombre = call.argument<String>("nombre") ?: ""
                    val metodo = call.method
                    val bytes = call.argument<ByteArray>("bytes")
                    val mime = call.argument<String>("mime") ?: "application/octet-stream"
                    Thread {
                        try {
                            val r: Any? = when (metodo) {
                                "listarCarpeta" -> CarpetaCompartida.listar(this, arbol)
                                "leerDeCarpeta" -> CarpetaCompartida.leer(this, arbol, nombre)
                                else -> { CarpetaCompartida.escribir(this, arbol, nombre, mime, bytes, null); true }
                            }
                            runOnUiThread { result.success(r) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("carpeta", e.message, null) }
                        }
                    }.start()
                }
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
        if (requestCode == pedirCarpeta) {
            val res = pendiente ?: return
            pendiente = null
            val uri = data?.data
            if (resultCode != Activity.RESULT_OK || uri == null) {
                res.success(null)
            } else {
                try {
                    contentResolver.takePersistableUriPermission(uri,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                    res.success(mapOf("uri" to uri.toString(), "nombre" to CarpetaCompartida.nombre(this, uri)))
                } catch (e: Exception) {
                    res.error("carpeta", e.message, null)
                }
            }
            return
        }
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

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        leerIntent(intent, true)
    }

    /** Anymyst Script manda el guion con ACTION_SEND. */
    private fun leerIntent(i: Intent?, avisar: Boolean) {
        if (i == null || i.action != Intent.ACTION_SEND) return
        val uri: Uri? = (if (Build.VERSION.SDK_INT >= 33) {
            i.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            @Suppress("DEPRECATION") i.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
        }) ?: i.clipData?.let { if (it.itemCount > 0) it.getItemAt(0).uri else null }
        i.action = null
        if (uri == null) return
        try {
            var nombre = "guion.anms"
            contentResolver.query(uri, null, null, null, null)?.use { c ->
                val k = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (k >= 0 && c.moveToFirst()) nombre = c.getString(k)
            }
            val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() } ?: return
            val m = mapOf("nombre" to nombre, "bytes" to bytes)
            if (avisar && canalArchivos != null) canalArchivos?.invokeMethod("recibido", m) else recibido = m
        } catch (_: Exception) {
        }
    }
}
