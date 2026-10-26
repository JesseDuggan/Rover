package ai.myrover.rover

// Called on the UI thread. Late callbacks may only settle their own utterance.
internal class PendingUtterance<T> {
    private var id: String? = null
    private var value: T? = null

    fun replace(utteranceId: String, result: T): T? {
        val previous = clear()
        id = utteranceId
        value = result
        return previous
    }

    fun take(utteranceId: String?): T? =
        if (utteranceId != null && utteranceId == id) clear() else null

    fun clear(): T? {
        val previous = value
        value = null
        id = null
        return previous
    }
}
