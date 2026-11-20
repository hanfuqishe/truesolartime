package com.realsuntime.solartime.widget

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 桌面卡片地名对齐：**不用 setGravity**（Android 10 的 RemoteViews 不支持，会在桌面进程抛异常），
 * 改成两套同款 TextView 用可见性切换：档 1 居中、档 0/2/3 不居中。
 */
class WidgetCityAlignTest {

    @Test
    fun onlyTierOneCentersTheCityName() {
        assertTrue(WidgetUpdater.cityAlignmentIsCentered(1))
        assertFalse(WidgetUpdater.cityAlignmentIsCentered(0))
        assertFalse(WidgetUpdater.cityAlignmentIsCentered(2))
        assertFalse(WidgetUpdater.cityAlignmentIsCentered(3))
    }
}