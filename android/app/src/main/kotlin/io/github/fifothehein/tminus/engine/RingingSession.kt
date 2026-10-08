package io.github.fifothehein.tminus.engine

import java.util.concurrent.CopyOnWriteArraySet

/**
 * The alerts ringing right now, shared in-process by RingingService, AlarmActivity and
 * AndroidAlertPresenter. Main thread only.
 */
object RingingSession {
    private val listeners = CopyOnWriteArraySet<(List<PlannedAlert>) -> Unit>()

    var alerts: List<PlannedAlert> = emptyList()
        private set

    val ids: Set<String> get() = alerts.map { it.id }.toSet()

    fun add(new: List<PlannedAlert>) = set((alerts + new).distinctBy { it.id })

    fun remove(ids: Collection<String>) {
        if (alerts.any { it.id in ids }) set(alerts.filterNot { it.id in ids })
    }

    fun clear() = set(emptyList())

    /** Returns a function that removes [listener]. */
    fun observe(listener: (List<PlannedAlert>) -> Unit): () -> Unit {
        listeners.add(listener)
        return { listeners.remove(listener) }
    }

    private fun set(value: List<PlannedAlert>) {
        alerts = value
        listeners.forEach { it(value) }
    }
}
