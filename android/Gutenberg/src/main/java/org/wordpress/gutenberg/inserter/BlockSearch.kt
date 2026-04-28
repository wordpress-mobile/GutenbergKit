package org.wordpress.gutenberg.inserter

import org.wordpress.gutenberg.model.BlockType

/**
 * Weighted fuzzy search for [BlockType]. Ports
 * `ios/Sources/GutenbergKit/Sources/Helpers/SearchEngine.swift` so the Android
 * inserter ranks results identically to iOS.
 *
 * Fields are scored in priority order — title, name, keywords, description,
 * category. Exact and prefix matches dominate; a Levenshtein fallback catches
 * near-misses on short queries.
 */
internal fun searchBlocks(query: String, blocks: List<BlockType>): List<BlockType> {
    val normalized = query.lowercase().trim()
    if (normalized.isEmpty()) return blocks
    return blocks
        .map { it to scoreBlock(it, normalized) }
        .filter { it.second > 0.0 }
        .sortedByDescending { it.second }
        .map { it.first }
}

private const val MAX_EDIT_DISTANCE = 2
private const val MIN_SIMILARITY_THRESHOLD = 0.7
private const val EXACT_MATCH_MULTIPLIER = 2.0
private const val PREFIX_MATCH_MULTIPLIER = 1.5
private const val WORD_PREFIX_MATCH_MULTIPLIER = 0.8
private const val FUZZY_MATCH_MULTIPLIER = 0.6
private const val FULL_FIELD_FUZZY_DAMPEN = 0.7
private const val FULL_FIELD_FUZZY_MAX_QUERY_LEN = 10

private const val WEIGHT_TITLE = 10.0
private const val WEIGHT_NAME = 8.0
private const val WEIGHT_KEYWORD = 5.0
private const val WEIGHT_DESCRIPTION = 2.0
private const val WEIGHT_CATEGORY = 2.0

private data class SearchField(val content: String, val weight: Double, val allowFuzzy: Boolean)

private fun BlockType.searchableFields(): List<SearchField> = buildList {
    title?.let { add(SearchField(it, WEIGHT_TITLE, allowFuzzy = true)) }
    add(SearchField(name, WEIGHT_NAME, allowFuzzy = false))
    keywords.forEach { add(SearchField(it, WEIGHT_KEYWORD, allowFuzzy = true)) }
    description?.let { add(SearchField(it, WEIGHT_DESCRIPTION, allowFuzzy = false)) }
    category?.let { add(SearchField(it, WEIGHT_CATEGORY, allowFuzzy = true)) }
}

private fun scoreBlock(block: BlockType, query: String): Double =
    block.searchableFields().sumOf { field ->
        if (field.content.isEmpty()) 0.0
        else fieldScore(field.content.lowercase(), query, field.weight, field.allowFuzzy)
    }

private fun fieldScore(field: String, query: String, weight: Double, allowFuzzy: Boolean): Double {
    if (field.isEmpty() || query.isEmpty()) return 0.0
    val literal = literalMatchScore(field, query, weight)
    if (literal != null) return literal
    if (!allowFuzzy) return 0.0
    return fuzzyMatchScore(field, query, weight)
}

private fun literalMatchScore(field: String, query: String, weight: Double): Double? = when {
    field == query -> weight * EXACT_MATCH_MULTIPLIER
    field.startsWith(query) -> weight * PREFIX_MATCH_MULTIPLIER
    field.contains(query) -> weight
    else -> null
}

private fun fuzzyMatchScore(field: String, query: String, weight: Double): Double {
    field.split(' ').forEach { word ->
        val wordScore = wordFuzzyScore(word, query, weight)
        if (wordScore > 0.0) return wordScore
    }
    if (query.length <= FULL_FIELD_FUZZY_MAX_QUERY_LEN) {
        val fieldSimilarity = similarity(field, query)
        if (fieldSimilarity >= MIN_SIMILARITY_THRESHOLD) {
            return weight * fieldSimilarity * FUZZY_MATCH_MULTIPLIER * FULL_FIELD_FUZZY_DAMPEN
        }
    }
    return 0.0
}

private fun wordFuzzyScore(word: String, query: String, weight: Double): Double {
    if (word.startsWith(query)) return weight * WORD_PREFIX_MATCH_MULTIPLIER
    val wordSimilarity = similarity(word, query)
    if (wordSimilarity >= MIN_SIMILARITY_THRESHOLD) {
        return weight * wordSimilarity * FUZZY_MATCH_MULTIPLIER
    }
    return 0.0
}

private fun similarity(a: String, b: String): Double {
    if (a.isEmpty() || b.isEmpty()) return 0.0
    val distance = levenshtein(a, b)
    val maxLen = maxOf(a.length, b.length)
    if (distance > minOf(MAX_EDIT_DISTANCE, maxLen / 3)) return 0.0
    return 1.0 - distance.toDouble() / maxLen
}

private fun levenshtein(a: String, b: String): Int {
    if (a.isEmpty()) return b.length
    if (b.isEmpty()) return a.length
    val matrix = Array(a.length + 1) { IntArray(b.length + 1) }
    for (i in 0..a.length) matrix[i][0] = i
    for (j in 0..b.length) matrix[0][j] = j
    for (i in 1..a.length) {
        for (j in 1..b.length) {
            val cost = if (a[i - 1] == b[j - 1]) 0 else 1
            matrix[i][j] = minOf(
                matrix[i - 1][j] + 1,
                matrix[i][j - 1] + 1,
                matrix[i - 1][j - 1] + cost,
            )
        }
    }
    return matrix[a.length][b.length]
}
