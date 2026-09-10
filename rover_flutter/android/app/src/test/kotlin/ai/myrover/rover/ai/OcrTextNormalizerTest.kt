package ai.myrover.rover.ai

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class OcrTextNormalizerTest {
    @Test
    fun normalizesWhitespaceWithoutChangingContent() {
        assertEquals(
            "Westport Museum\nOpen daily",
            OcrTextNormalizer.normalize("  Westport   Museum\r\n\n\nOpen\tdaily  "),
        )
    }

    @Test
    fun boundsReturnedText() {
        val result = OcrTextNormalizer.normalize("a".repeat(3_000))

        assertEquals(2_000, result.length)
        assertTrue(result.all { it == 'a' })
    }
}
