package com.example.unsync

import android.app.Activity
import android.content.ContentResolver
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Account backup files in a folder the user picked (Storage Access Framework).
 * The folder is outside the app, so the backup survives an uninstall. The app
 * keeps a persisted permission to write there, so backups can be refreshed
 * without asking again.
 */
class BackupDocuments(private val activity: Activity) {
    companion object {
        const val CHANNEL = "uk.unsync.messenger/backup"
        const val PICK_FOLDER = 4711
        const val PICK_FILE = 4712
    }

    private var pendingFolder: MethodChannel.Result? = null
    private var pendingFile: MethodChannel.Result? = null
    private val resolver: ContentResolver get() = activity.contentResolver

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "pickFolder" -> {
                    pendingFolder?.success(null)
                    pendingFolder = result
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or
                            Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                            Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
                    )
                    activity.startActivityForResult(intent, PICK_FOLDER)
                }
                "pickFile" -> {
                    pendingFile?.success(null)
                    pendingFile = result
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
                        .addCategory(Intent.CATEGORY_OPENABLE)
                        .setType("*/*")
                    activity.startActivityForResult(intent, PICK_FILE)
                }
                "isAvailable" -> result.success(isAvailable(Uri.parse(call.argument<String>("uri")!!)))
                "write" -> {
                    write(
                        Uri.parse(call.argument<String>("uri")!!),
                        call.argument<String>("name")!!,
                        call.argument<ByteArray>("bytes")!!
                    )
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("backup_failed", e.message ?: e.javaClass.simpleName, null)
        }
    }

    /** Returns true when this activity result belonged to the backup picker. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        when (requestCode) {
            PICK_FOLDER -> {
                val result = pendingFolder ?: return true
                pendingFolder = null
                val uri = data?.data
                if (resultCode != Activity.RESULT_OK || uri == null) {
                    result.success(null)
                    return true
                }
                try {
                    resolver.takePersistableUriPermission(
                        uri,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                    )
                    result.success(mapOf("uri" to uri.toString(), "name" to folderName(uri)))
                } catch (e: Exception) {
                    result.error("backup_failed", e.message ?: "Could not keep access to the folder", null)
                }
                return true
            }
            PICK_FILE -> {
                val result = pendingFile ?: return true
                pendingFile = null
                val uri = data?.data
                if (resultCode != Activity.RESULT_OK || uri == null) {
                    result.success(null)
                    return true
                }
                try {
                    val bytes = resolver.openInputStream(uri)!!.use { it.readBytes() }
                    result.success(mapOf("name" to displayName(uri), "bytes" to bytes))
                } catch (e: Exception) {
                    result.error("backup_failed", e.message ?: "Could not read the file", null)
                }
                return true
            }
        }
        return false
    }

    private fun isAvailable(tree: Uri): Boolean {
        val granted = resolver.persistedUriPermissions.any { it.uri == tree && it.isWritePermission }
        if (!granted) return false
        return try {
            val doc = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
            resolver.query(doc, arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID), null, null, null)
                ?.use { it.moveToFirst() } ?: false
        } catch (e: Exception) {
            false
        }
    }

    /** Writes [name] in the folder: a temporary file first, then it replaces the old one. */
    private fun write(tree: Uri, name: String, bytes: ByteArray) {
        val parent = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
        val tempName = "$name.tmp"
        findChild(tree, tempName)?.let { DocumentsContract.deleteDocument(resolver, it) }
        val temp = DocumentsContract.createDocument(resolver, parent, "application/octet-stream", tempName)
            ?: throw IllegalStateException("The backup folder refused a new file")
        resolver.openOutputStream(temp, "wt")!!.use { it.write(bytes) }
        findChild(tree, name)?.let { DocumentsContract.deleteDocument(resolver, it) }
        val renamed = try {
            DocumentsContract.renameDocument(resolver, temp, name)
        } catch (e: Exception) {
            null
        }
        if (renamed == null) {
            // Some folders cannot rename: write the final file directly instead.
            val target = DocumentsContract.createDocument(resolver, parent, "application/octet-stream", name)
                ?: throw IllegalStateException("The backup folder refused a new file")
            resolver.openOutputStream(target, "wt")!!.use { it.write(bytes) }
            DocumentsContract.deleteDocument(resolver, temp)
        }
    }

    private fun findChild(tree: Uri, name: String): Uri? {
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
        resolver.query(
            children,
            arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME),
            null, null, null
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                if (cursor.getString(1) == name) {
                    return DocumentsContract.buildDocumentUriUsingTree(tree, cursor.getString(0))
                }
            }
        }
        return null
    }

    private fun folderName(tree: Uri): String = try {
        val doc = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
        resolver.query(doc, arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)
            ?.use { if (it.moveToFirst()) it.getString(0) else null } ?: tree.lastPathSegment ?: "Folder"
    } catch (e: Exception) {
        tree.lastPathSegment ?: "Folder"
    }

    private fun displayName(uri: Uri): String = try {
        resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { if (it.moveToFirst()) it.getString(0) else null } ?: "backup"
    } catch (e: Exception) {
        "backup"
    }
}
