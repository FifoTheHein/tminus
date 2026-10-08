package io.github.fifothehein.tminus.engine

/** Picks the first tone that opens (spec §9: a missing custom tone falls back to the default alarm tone). */
object ToneFallback {
    /** Returns the index and result of the first candidate [open] accepts, or null if none does. */
    fun <S, P> firstPlayable(candidates: List<S>, open: (S) -> P): Pair<Int, P>? {
        candidates.forEachIndexed { index, candidate ->
            try {
                return index to open(candidate)
            } catch (e: Exception) {
                // This tone is unusable; try the next one.
            }
        }
        return null
    }
}
