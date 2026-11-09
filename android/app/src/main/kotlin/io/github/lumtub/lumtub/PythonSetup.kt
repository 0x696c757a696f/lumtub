package io.github.lumtub.lumtub

import android.content.Context
import android.system.Os
import java.io.File
import java.util.zip.ZipFile

/**
 * Python for yt-dlp, from youtubedl-android's packages: libpython.so is the
 * interpreter, run from the app's library folder (the only place Android 10
 * and later lets an app start a program of its own), libpython.zip.so its
 * standard library, unpacked once per app version, and libqjs.so QuickJS
 * for YouTube's JavaScript challenges. Dart starts the processes itself
 * (lib/android_python.dart); this only gets the files ready.
 */
object PythonSetup {
    private const val READY = ".lumtub-ready"

    /** The paths Dart needs, or null when this APK carries no Python. */
    @Synchronized
    fun prepare(context: Context): Map<String, String>? {
        val libraries = File(context.applicationInfo.nativeLibraryDir)
        val python = File(libraries, "libpython.so")
        val packed = File(libraries, "libpython.zip.so")
        if (!python.exists() || !packed.exists()) return null
        val home = File(context.noBackupFilesDir, "python")
        val stamp = "${packed.length()} ${packed.lastModified()}"
        val ready = File(home, READY)
        if (!ready.exists() || ready.readText() != stamp) {
            home.deleteRecursively()
            val partial = File(context.noBackupFilesDir, "python.partial")
            partial.deleteRecursively()
            unzip(packed, partial)
            if (!partial.renameTo(home)) throw IllegalStateException("could not move Python into place")
            File(home, READY).writeText(stamp)
        }
        val bundled = copyBundledYtDlp(context)
        val usr = File(home, "usr")
        return buildMap {
            put("python", python.absolutePath)
            File(libraries, "libqjs.so").takeIf { it.exists() }?.let { put("quickjs", it.absolutePath) }
            put("home", usr.absolutePath)
            put("libraries", File(usr, "lib").absolutePath)
            put("certificates", File(usr, "etc/tls/cert.pem").absolutePath)
            put("programs", libraries.absolutePath)
            put("temporary", context.cacheDir.absolutePath)
            bundled?.let { put("bundledYtDlp", it.absolutePath) }
        }
    }

    /**
     * The yt-dlp the library carries, copied out for Dart to install when
     * none is there yet; a newer one comes with the update check.
     */
    private fun copyBundledYtDlp(context: Context): File? {
        val id = context.resources.getIdentifier("ytdlp", "raw", context.packageName)
        if (id == 0) return null
        val out = File(context.cacheDir, "yt-dlp-bundled")
        if (!out.exists()) {
            val partial = File(context.cacheDir, "yt-dlp-bundled.partial")
            context.resources.openRawResource(id).use { input -> partial.outputStream().use { input.copyTo(it) } }
            partial.renameTo(out)
        }
        return out
    }

    private fun unzip(zip: File, into: File) {
        into.mkdirs()
        val root = into.canonicalPath + File.separator
        ZipFile(zip).use { archive ->
            for (entry in archive.entries()) {
                val target = File(into, entry.name)
                if (!target.canonicalPath.startsWith(root)) {
                    throw SecurityException("${entry.name} points outside the folder")
                }
                val mode = unixMode(archive, entry)
                when {
                    entry.isDirectory -> target.mkdirs()
                    mode and 0xF000 == 0xA000 -> {
                        target.parentFile?.mkdirs()
                        val link = archive.getInputStream(entry).use { String(it.readBytes(), Charsets.UTF_8) }
                        Os.symlink(link, target.path)
                    }
                    else -> {
                        target.parentFile?.mkdirs()
                        archive.getInputStream(entry).use { input -> target.outputStream().use { input.copyTo(it) } }
                    }
                }
            }
        }
    }

    /** java.util.zip hides the external attributes; read them from the central directory. */
    private fun unixMode(archive: ZipFile, entry: java.util.zip.ZipEntry): Int = modes(archive)[entry.name] ?: 0

    private var modeCache: Pair<String, Map<String, Int>>? = null

    private fun modes(archive: ZipFile): Map<String, Int> {
        modeCache?.let { if (it.first == archive.name) return it.second }
        val found = HashMap<String, Int>()
        java.io.RandomAccessFile(archive.name, "r").use { file ->
            val length = file.length()
            val tail = minOf(length, 65_557L).toInt()
            val buffer = ByteArray(tail)
            file.seek(length - tail)
            file.readFully(buffer)
            var end = -1
            for (i in tail - 22 downTo 0) {
                if (le32(buffer, i) == 0x06054b50) { end = i; break }
            }
            if (end < 0) return found
            val count = le16(buffer, end + 10)
            val size = le32(buffer, end + 12).toLong() and 0xFFFFFFFFL
            val offset = le32(buffer, end + 16).toLong() and 0xFFFFFFFFL
            val directory = ByteArray(size.toInt())
            file.seek(offset)
            file.readFully(directory)
            var at = 0
            repeat(count) {
                if (at + 46 > directory.size || le32(directory, at) != 0x02014b50) return@repeat
                val nameLength = le16(directory, at + 28)
                val extraLength = le16(directory, at + 30)
                val commentLength = le16(directory, at + 32)
                val external = le32(directory, at + 38)
                val name = String(directory, at + 46, nameLength, Charsets.UTF_8)
                found[name] = (external ushr 16) and 0xFFFF
                at += 46 + nameLength + extraLength + commentLength
            }
        }
        modeCache = archive.name to found
        return found
    }

    private fun le16(b: ByteArray, at: Int) = (b[at].toInt() and 0xFF) or ((b[at + 1].toInt() and 0xFF) shl 8)
    private fun le32(b: ByteArray, at: Int) = le16(b, at) or (le16(b, at + 2) shl 16)
}
