package ai.myrover.rover.ai

import ai.myrover.rover.ai.generated.NativeRoverAiOperation
import ai.myrover.rover.ai.generated.NativeRoverAiRequest
import ai.myrover.rover.ai.generated.NativeRoverAiResult
import ai.myrover.rover.ai.generated.NativeRoverAiResultStatus
import android.content.Context
import android.net.Uri
import com.google.android.gms.tasks.Task
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import java.io.File
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.suspendCancellableCoroutine

internal class OnDeviceLensProvider(
    private val context: Context,
) {
    suspend fun recognizeText(request: NativeRoverAiRequest): NativeRoverAiResult {
        val started = System.currentTimeMillis()
        val imageFile = validatedImage(request.localImagePath)
            ?: return result(
                request = request,
                status = NativeRoverAiResultStatus.DENIED,
                diagnosticCode = "lens_ocr_invalid_image",
                durationMilliseconds = elapsed(started),
            )

        val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        return try {
            val image = InputImage.fromFilePath(context, Uri.fromFile(imageFile))
            val recognized = recognizer.process(image).awaitTask()
            val text = OcrTextNormalizer.normalize(recognized.text)
            result(
                request = request,
                status = NativeRoverAiResultStatus.SUCCESS,
                diagnosticCode = if (text.isEmpty()) {
                    "lens_ocr_no_text"
                } else {
                    "lens_ocr_completed"
                },
                durationMilliseconds = elapsed(started),
                text = text.ifEmpty { null },
            )
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            result(
                request = request,
                status = NativeRoverAiResultStatus.ERROR,
                diagnosticCode = "lens_ocr_failed",
                durationMilliseconds = elapsed(started),
            )
        } finally {
            recognizer.close()
        }
    }

    private fun validatedImage(path: String?): File? {
        if (path.isNullOrBlank()) {
            return null
        }
        val file = try {
            File(path).canonicalFile
        } catch (_: Throwable) {
            return null
        }
        val cacheRoot = context.cacheDir.canonicalFile
        val codeCacheRoot = context.codeCacheDir.canonicalFile
        val inAppCache = file.isWithin(cacheRoot) || file.isWithin(codeCacheRoot)
        return file.takeIf {
            inAppCache &&
                it.isFile &&
                it.length() in 1..MAX_IMAGE_BYTES
        }
    }

    private fun File.isWithin(root: File): Boolean =
        path == root.path || path.startsWith(root.path + File.separator)

    private fun result(
        request: NativeRoverAiRequest,
        status: NativeRoverAiResultStatus,
        diagnosticCode: String,
        durationMilliseconds: Long,
        text: String? = null,
    ) = NativeRoverAiResult(
        correlationId = request.correlationId,
        status = status,
        provider = PROVIDER_NAME,
        operation = NativeRoverAiOperation.LENS_OCR,
        durationMilliseconds = durationMilliseconds,
        fallbackUsed = false,
        diagnosticCode = diagnosticCode,
        text = text,
        candidateLabels = emptyList(),
        evidenceIds = emptyList(),
        policyDecisions = listOf("local_only", "candidate_unverified"),
    )

    private fun elapsed(started: Long): Long =
        (System.currentTimeMillis() - started).coerceAtLeast(0)

    companion object {
        private const val PROVIDER_NAME = "ML Kit Text Recognition v2"
        private const val MAX_IMAGE_BYTES = 20L * 1024L * 1024L
    }
}

internal object OcrTextNormalizer {
    private const val MAX_TEXT_LENGTH = 2_000

    fun normalize(value: String): String = value
        .lineSequence()
        .map { line -> line.replace(Regex("\\s+"), " ").trim() }
        .filter { line -> line.isNotEmpty() }
        .joinToString("\n")
        .take(MAX_TEXT_LENGTH)
}

private suspend fun <T> Task<T>.awaitTask(): T =
    suspendCancellableCoroutine { continuation ->
        addOnSuccessListener { value ->
            if (continuation.isActive) {
                continuation.resume(value)
            }
        }
        addOnFailureListener { error ->
            if (continuation.isActive) {
                continuation.resumeWithException(error)
            }
        }
        addOnCanceledListener {
            continuation.cancel()
        }
    }
