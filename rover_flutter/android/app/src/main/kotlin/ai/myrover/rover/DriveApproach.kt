package ai.myrover.rover

import kotlin.math.*

internal data class DrivePoint(val lat: Double, val lon: Double)
internal data class DriveStop(val id: String, val name: String, val point: DrivePoint, val audio: String?, val expires: Long?)
internal data class DriveFix(val point: DrivePoint, val speed: Double, val accuracy: Double, val ageMs: Long)

internal fun driveDistance(a: DrivePoint, b: DrivePoint): Double {
    val dLat = Math.toRadians(b.lat - a.lat)
    val dLon = Math.toRadians(b.lon - a.lon)
    val h = sin(dLat / 2).pow(2) + cos(Math.toRadians(a.lat)) * cos(Math.toRadians(b.lat)) * sin(dLon / 2).pow(2)
    return 6371000 * 2 * asin(sqrt(h.coerceIn(0.0, 1.0)))
}

// Linear-reference the planned road route, rather than triggering across a bay
// merely because a stop is geographically close.
internal class DriveApproach(private val route: List<DrivePoint>, val stops: List<DriveStop>) {
    private val lengths = route.zipWithNext { a, b -> driveDistance(a, b) }
    private val offsets = mutableListOf(0.0).apply { lengths.forEach { add(last() + it) } }
    private val targets = stops.map { project(it.point).first }
    private val consumed = mutableSetOf<Int>()
    private var previous: Double? = null
    private var lastPlayed = Long.MIN_VALUE
    var arrived = false
        private set

    private fun project(p: DrivePoint): Pair<Double, Double> {
        var nearest = Double.POSITIVE_INFINITY
        var along = 0.0
        for (i in lengths.indices) {
            val a = route[i]
            val b = route[i + 1]
            val scale = cos(Math.toRadians(p.lat))
            val dx = (b.lon - a.lon) * scale
            val dy = b.lat - a.lat
            val px = (p.lon - a.lon) * scale
            val py = p.lat - a.lat
            val t = if (dx * dx + dy * dy == 0.0) 0.0 else ((px * dx + py * dy) / (dx * dx + dy * dy)).coerceIn(0.0, 1.0)
            val candidate = DrivePoint(a.lat + t * (b.lat - a.lat), a.lon + t * (b.lon - a.lon))
            val distance = driveDistance(p, candidate)
            if (distance < nearest) {
                nearest = distance
                along = offsets[i] + lengths[i] * t
            }
        }
        return along to nearest
    }

    fun candidate(fix: DriveFix, now: Long): Int? {
        if (!fix.accuracy.isFinite() || fix.accuracy > 75 || fix.ageMs !in 0..20000 ||
            !fix.speed.isFinite() || fix.speed < 0 || fix.speed > 60) return null
        val (along, offRoute) = project(fix.point)
        if (offRoute > 100) { previous = null; return null }
        val before = previous
        previous = along
        stops.indices.filter { along > targets[it] + 250 }.forEach { consumed.add(it) }
        arrived = stops.isNotEmpty() && driveDistance(fix.point, stops.last().point) < 100 &&
            (before != null && along > 100)
        if (before == null || along - before < 8 || fix.speed < 1.5 ||
            (lastPlayed != Long.MIN_VALUE && now - lastPlayed < 90000)) return null
        val next = stops.indices.firstOrNull { it !in consumed } ?: return null
        val remaining = targets[next] - along
        if (remaining < -100 || remaining > (fix.speed * 150).coerceIn(250.0, 3000.0)) return null
        if (stops[next].audio == null || (stops[next].expires?.let { it <= now } == true)) {
            consumed.add(next)
            return null
        }
        return next
    }

    fun played(index: Int, now: Long) {
        consumed.add(index)
        lastPlayed = now
    }
}

