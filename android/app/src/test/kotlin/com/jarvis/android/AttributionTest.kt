package com.jarvis.android

import org.junit.Assert.assertEquals
import org.junit.Test

class AttributionTest {
    @Test fun nameAndRepoMatchPermission() {
        assertEquals("Jarvis for Android", Attribution.APP_NAME)
        assertEquals("https://github.com/Ak2201/jarvis", Attribution.REPO_URL)
    }
}
