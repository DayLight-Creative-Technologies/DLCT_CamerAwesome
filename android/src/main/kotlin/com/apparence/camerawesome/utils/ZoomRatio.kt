package com.apparence.camerawesome.utils

/**
 * DLCT: one owner for how the plugin's normalized zoom (0.0 = min, 1.0 = max) becomes a CameraX zoom ratio.
 *
 * The mapping is LINEAR IN RATIO, the same as the iOS side (ZoomUtils.m) and the contract consumers rely on:
 * getMinZoom()/getMaxZoom() report ratios and a consumer computes `normalized = (ratio - min) / (max - min)`.
 * CameraX's own `setLinearZoom` is linear in crop width instead, so the same normalized value gave a different
 * field of view (a "2x" button on a 1x-8x camera came out about 1.14x).
 */
object ZoomRatio {
    fun forNormalized(normalized: Float, minRatio: Float, maxRatio: Float): Float {
        val clamped = normalized.coerceIn(0f, 1f)
        return (minRatio + clamped * (maxRatio - minRatio)).coerceIn(minRatio, maxRatio)
    }
}
