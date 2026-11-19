package com.apparence.camerawesome.utils

import org.junit.Assert.assertEquals
import org.junit.Test

class ZoomRatioTest {
    private val delta = 1e-5f

    @Test
    fun endpointsAreMinAndMax() {
        assertEquals(1f, ZoomRatio.forNormalized(0f, 1f, 8f), delta)
        assertEquals(8f, ZoomRatio.forNormalized(1f, 1f, 8f), delta)
    }

    @Test
    fun mappingIsLinearInRatioSoTwoXIsTwoX() {
        // A consumer asks for 2x on a 1x-8x camera with normalized = (2 - 1) / (8 - 1).
        assertEquals(2f, ZoomRatio.forNormalized((2f - 1f) / (8f - 1f), 1f, 8f), delta)
        // Ultra-wide in the logical camera: 0.5x-10x, 1x = (1 - 0.5) / 9.5.
        assertEquals(1f, ZoomRatio.forNormalized((1f - 0.5f) / (10f - 0.5f), 0.5f, 10f), delta)
    }

    @Test
    fun outOfRangeIsClamped() {
        assertEquals(1f, ZoomRatio.forNormalized(-0.3f, 1f, 8f), delta)
        assertEquals(8f, ZoomRatio.forNormalized(1.7f, 1f, 8f), delta)
    }
}
