package com.anymyst.anymyst_plan

import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract
import java.io.FileInputStream

/** Escribe archivos en una carpeta elegida por la usuaria (para pasarlos al PC). */
object CarpetaCompartida {
    fun nombre(ctx: Context, arbol: Uri): String {
        return try {
            val doc = DocumentsContract.buildDocumentUriUsingTree(arbol, DocumentsContract.getTreeDocumentId(arbol))
            ctx.contentResolver.query(doc, arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)
                ?.use { c -> if (c.moveToFirst()) c.getString(0) else null } ?: "Carpeta"
        } catch (_: Exception) {
            "Carpeta"
        }
    }

    /** (nombre, fecha en ms) de los archivos de la carpeta. */
    fun listar(ctx: Context, arbolTexto: String): List<Map<String, Any>> {
        val arbol = Uri.parse(arbolTexto)
        val hijos = DocumentsContract.buildChildDocumentsUriUsingTree(arbol, DocumentsContract.getTreeDocumentId(arbol))
        val r = mutableListOf<Map<String, Any>>()
        ctx.contentResolver.query(hijos,
            arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME, DocumentsContract.Document.COLUMN_LAST_MODIFIED),
            null, null, null)?.use { c ->
            while (c.moveToNext()) {
                r.add(mapOf("nombre" to (c.getString(0) ?: ""), "fecha" to c.getLong(1)))
            }
        }
        return r
    }

    fun leer(ctx: Context, arbolTexto: String, nombre: String): ByteArray? {
        val arbol = Uri.parse(arbolTexto)
        val hijos = DocumentsContract.buildChildDocumentsUriUsingTree(arbol, DocumentsContract.getTreeDocumentId(arbol))
        var destino: Uri? = null
        ctx.contentResolver.query(hijos,
            arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME),
            null, null, null)?.use { c ->
            while (c.moveToNext()) {
                if (c.getString(1) == nombre) {
                    destino = DocumentsContract.buildDocumentUriUsingTree(arbol, c.getString(0))
                    break
                }
            }
        }
        val d = destino ?: return null
        return ctx.contentResolver.openInputStream(d)?.use { it.readBytes() }
    }

    fun escribir(ctx: Context, arbolTexto: String, nombre: String, mime: String, bytes: ByteArray?, rutaOrigen: String?) {
        val arbol = Uri.parse(arbolTexto)
        val idPadre = DocumentsContract.getTreeDocumentId(arbol)
        val padre = DocumentsContract.buildDocumentUriUsingTree(arbol, idPadre)
        val hijos = DocumentsContract.buildChildDocumentsUriUsingTree(arbol, idPadre)
        var destino: Uri? = null
        ctx.contentResolver.query(hijos,
            arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME),
            null, null, null)?.use { c ->
            while (c.moveToNext()) {
                if (c.getString(1) == nombre) {
                    destino = DocumentsContract.buildDocumentUriUsingTree(arbol, c.getString(0))
                    break
                }
            }
        }
        if (destino == null) {
            destino = DocumentsContract.createDocument(ctx.contentResolver, padre, mime, nombre)
        }
        val d = destino ?: throw IllegalStateException("No pude crear el archivo en la carpeta")
        ctx.contentResolver.openOutputStream(d, "wt")?.use { salida ->
            if (rutaOrigen != null) {
                FileInputStream(rutaOrigen).use { it.copyTo(salida) }
            } else {
                salida.write(bytes ?: ByteArray(0))
            }
        } ?: throw IllegalStateException("No pude escribir en la carpeta")
    }
}
