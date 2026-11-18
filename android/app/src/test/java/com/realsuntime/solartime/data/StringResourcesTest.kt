package com.realsuntime.solartime.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.w3c.dom.Element
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory

/**
 * 三份 `strings.xml`（英文 / 简体 / 繁體）的**结构**校验。
 *
 * 需求要求「三份 key 集合保持一致、XML 合法」，这类事只有机器检查才靠得住：
 * 漏一个 key 在运行期只会静默回退到英文（`values`），肉眼很难发现。
 *
 * 这个测试只读磁盘上的资源文件（纯 JVM，不需要 Android）。
 */
class StringResourcesTest {

    private val locales = listOf("values", "values-zh", "values-b+zh+Hant")

    private fun resDir(locale: String): File = findFile("src/main/res/$locale/strings.xml").parentFile

    private fun stringsFile(locale: String): File = File(resDir(locale), "strings.xml")

    /** 从测试工作目录开始逐级往上找（Gradle 的 unit test 工作目录通常是模块目录）。 */
    private fun findFile(relative: String): File {
        val direct = listOf(File(relative), File("app/$relative"))
        direct.firstOrNull { it.isFile }?.let { return it }
        var dir: File? = File("").absoluteFile
        while (dir != null) {
            for (candidate in listOf(File(dir, relative), File(dir, "app/$relative"))) {
                if (candidate.isFile) return candidate
            }
            dir = dir.parentFile
        }
        throw AssertionError("找不到资源文件：$relative（工作目录 ${File("").absolutePath}）")
    }

    /** `name -> 文本`；XML 不合法会在这里直接抛异常，等价于「XML 合法」的断言。 */
    private fun readStrings(locale: String): Map<String, String> {
        val file = stringsFile(locale)
        val doc = DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(file)
        val nodes = doc.getElementsByTagName("string")
        val out = LinkedHashMap<String, String>()
        for (i in 0 until nodes.length) {
            val element = nodes.item(i) as Element
            val name = element.getAttribute("name")
            assertTrue("$locale 里有空的 name 属性", name.isNotEmpty())
            assertFalse("$locale 里 key 重复：$name", out.containsKey(name))
            out[name] = element.textContent.orEmpty()
        }
        assertTrue("$locale 里一个 string 都没读到", out.isNotEmpty())
        return out
    }

    @Test
    fun allLocaleFilesAreWellFormedXml() {
        for (locale in locales) {
            val file = stringsFile(locale)
            assertTrue("$locale/strings.xml 不存在", file.isFile)
            // 解析本身就是「XML 合法」的断言。
            assertTrue("$locale 的字符串数量应 > 100", readStrings(locale).size > 100)
        }
    }

    @Test
    fun allLocalesDeclareExactlyTheSameKeys() {
        val base = readStrings("values").keys
        for (locale in locales.drop(1)) {
            val keys = readStrings(locale).keys
            assertEquals("$locale 缺这些 key：${base - keys}", emptySet<String>(), base - keys)
            assertEquals("$locale 多出这些 key：${keys - base}", emptySet<String>(), keys - base)
            assertEquals("$locale 的 key 数量应与 values 一致", base.size, keys.size)
        }
    }

    /** 未知态的两条可见文案：三份都必须有，且不能是空串。 */
    @Test
    fun unknownLocationCopyExistsInEveryLocale() {
        for (locale in locales) {
            val strings = readStrings(locale)
            for (key in listOf("location_unavailable", "location_unavailable_hint")) {
                val value = strings[key]
                assertTrue("$locale 缺少 $key", value != null)
                assertTrue("$locale 的 $key 是空的", !value.isNullOrBlank())
            }
        }
        // 简体 / 繁體都是「定位不可用」；英文是 Location unavailable。
        assertEquals("定位不可用", readStrings("values-zh")["location_unavailable"])
        assertEquals("定位不可用", readStrings("values-b+zh+Hant")["location_unavailable"])
        assertEquals("Location unavailable", readStrings("values")["location_unavailable"])
    }
}
