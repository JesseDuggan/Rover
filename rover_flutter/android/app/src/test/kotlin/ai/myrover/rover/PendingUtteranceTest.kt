package ai.myrover.rover

import org.junit.Assert.*
import org.junit.Test

class PendingUtteranceTest {
    @Test fun lateStoryCallbackCannotCompletePoiOrResumedStory() {
        val pending = PendingUtterance<String>()
        pending.replace("story-1", "story")
        assertEquals("story", pending.clear())
        pending.replace("poi-1", "poi")
        assertNull(pending.take("story-1"))
        assertEquals("poi", pending.take("poi-1"))
        pending.replace("story-2", "resumed")
        assertNull(pending.take("poi-1"))
        assertEquals("resumed", pending.take("story-2"))
        assertNull(pending.take("story-2"))
    }

    @Test fun replacementAndStopSettleOnlyOnce() {
        val pending = PendingUtterance<String>()
        pending.replace("first", "one")
        assertEquals("one", pending.replace("second", "two"))
        assertNull(pending.take(null))
        assertNull(pending.take("first"))
        assertEquals("two", pending.clear())
        assertNull(pending.take("second"))
    }
}
