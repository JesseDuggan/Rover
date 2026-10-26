package ai.myrover.rover

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors

class MemoryThumbnails(private val context: Context, messenger: BinaryMessenger) {
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val channel = MethodChannel(messenger, "ai.myrover.rover/memories")
    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method != "thumbnail") result.notImplemented()
            else {
                val path = call.argument<String>("path")
                executor.execute {
                    val bytes = try { frame(path) } catch (_: Exception) { null }
                    main.post { result.success(bytes) }
                }
            }
        }
    }
    private fun frame(path: String?): ByteArray? {
        if (path == null) return null
        val file = File(path).canonicalFile
        val roots = listOf(context.filesDir.canonicalPath, context.cacheDir.canonicalPath)
        if (!roots.any { file.path.startsWith(it + File.separator) } || !file.isFile || file.extension != "mp4") return null
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(file.path)
            val image = if (Build.VERSION.SDK_INT >= 27) {
                retriever.getScaledFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST_SYNC, 480, 480)
            } else retriever.getFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
            if (image == null) return null
            try {
                val ratio = minOf(1.0, 480.0 / maxOf(image.width, image.height))
                val scaled = Bitmap.createScaledBitmap(image, maxOf(1, (image.width * ratio).toInt()), maxOf(1, (image.height * ratio).toInt()), true)
                try {
                    return ByteArrayOutputStream().use { output ->
                        scaled.compress(Bitmap.CompressFormat.JPEG, 75, output)
                        output.toByteArray()
                    }
                } finally { if (scaled !== image) scaled.recycle() }
            } finally { image.recycle() }
        } finally { retriever.release() }
    }
    fun dispose() {
        channel.setMethodCallHandler(null)
        executor.shutdown()
    }
}
