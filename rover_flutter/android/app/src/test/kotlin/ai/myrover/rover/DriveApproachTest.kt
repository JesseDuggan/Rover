package ai.myrover.rover

import org.junit.Assert.*
import org.junit.Test

class DriveApproachTest {
    private val route = listOf(DrivePoint(0.0, 0.0), DrivePoint(0.0, 0.1))
    private fun engine() = DriveApproach(route, listOf(
        DriveStop("one", "First", DrivePoint(0.0, 0.05), "audio", 999999999L),
        DriveStop("two", "Second", DrivePoint(0.0, 0.09), "audio", 999999999L)))
    private fun fix(lon: Double, speed: Double = 15.0, accuracy: Double = 10.0, age: Long = 0) =
        DriveFix(DrivePoint(0.0, lon), speed, accuracy, age)

    @Test fun approachesOnceAndInOrder() {
        val e = engine()
        assertNull(e.candidate(fix(0.03), 1000))
        assertEquals(0, e.candidate(fix(0.031), 6000))
        e.played(0, 6000)
        assertNull(e.candidate(fix(0.032), 11000))
        assertNull(e.candidate(fix(0.06), 21000))
        assertEquals(1, e.candidate(fix(0.071), 110000))
        e.played(1, 110000)
        assertNull(e.candidate(fix(0.072), 120000))
    }
    @Test fun rejectsBadFixesAndOppositeTravel() {
        val e = engine()
        assertNull(e.candidate(fix(0.03, accuracy = 100.0), 1000))
        assertNull(e.candidate(fix(0.031, age = 30000), 2000))
        assertNull(e.candidate(fix(0.032), 3000))
        assertNull(e.candidate(fix(0.031), 4000))
        assertNull(e.candidate(fix(0.033, speed = 0.0), 5000))
        assertNull(e.candidate(DriveFix(DrivePoint(0.01, 0.034), 15.0, 10.0, 0), 6000))
    }
    @Test fun distanceUsesRoadNotAcrossWater() {
        val e = DriveApproach(listOf(DrivePoint(0.0, 0.0), DrivePoint(0.0, 0.1),
            DrivePoint(0.01, 0.1), DrivePoint(0.01, 0.0)), listOf(
            DriveStop("far", "Across bay", DrivePoint(0.01, 0.0), "audio", null)))
        e.candidate(fix(0.001), 1000)
        assertNull(e.candidate(fix(0.002), 6000))
    }
    @Test fun skipsPassedAndExpiredStops() {
        val e = engine()
        e.candidate(fix(0.06), 1000)
        assertEquals(1, e.candidate(fix(0.071), 6000))
        val expired = DriveApproach(route, listOf(DriveStop("one", "Old", DrivePoint(0.0, 0.05), "audio", 1)))
        expired.candidate(fix(0.03), 1000)
        assertNull(expired.candidate(fix(0.031), 6000))
    }
    @Test fun arrivalAndNoAudioAreSafe() {
        val e = DriveApproach(route, listOf(DriveStop("one", "Silent", DrivePoint(0.0, 0.05), null, null)))
        e.candidate(fix(0.03), 1000)
        assertNull(e.candidate(fix(0.031), 6000))
        e.candidate(fix(0.05, speed = 0.0), 10000)
        assertTrue(e.arrived)
    }
}

