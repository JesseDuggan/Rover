package ai.myrover.rover.ai

import ai.myrover.rover.ai.generated.NativeRoverAiAvailability
import com.google.mlkit.genai.common.FeatureStatus
import org.junit.Assert.assertEquals
import org.junit.Test

class FeatureStatusMapperTest {
    @Test
    fun mapsKnownMlKitFeatureStates() {
        assertEquals(
            NativeRoverAiAvailability.AVAILABLE,
            FeatureStatusMapper.map(FeatureStatus.AVAILABLE),
        )
        assertEquals(
            NativeRoverAiAvailability.DOWNLOADABLE,
            FeatureStatusMapper.map(FeatureStatus.DOWNLOADABLE),
        )
        assertEquals(
            NativeRoverAiAvailability.DOWNLOADING,
            FeatureStatusMapper.map(FeatureStatus.DOWNLOADING),
        )
        assertEquals(
            NativeRoverAiAvailability.UNAVAILABLE,
            FeatureStatusMapper.map(FeatureStatus.UNAVAILABLE),
        )
    }

    @Test
    fun mapsUnexpectedFeatureStateToUnknown() {
        assertEquals(
            NativeRoverAiAvailability.UNKNOWN,
            FeatureStatusMapper.map(Int.MAX_VALUE),
        )
    }
}
