package com.daoban.shiftassistantpro

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.util.LruCache

/**
 * 班次色块的小位图。
 *
 * 为什么非要画位图：色块的颜色是**用户自选**的任意 ARGB（编辑器的取色盘），
 * 没法枚举成几个静态的 `<shape>` drawable；而运行期构造的 `GradientDrawable`
 * 又**传不进 RemoteViews**（宿主进程渲染，只认官方白名单里的东西 —— 它接受
 * drawable 资源 id 与 Bitmap，不接受 Drawable 对象）。所以只能自己画。
 *
 * 开销：一次刷新最多几十张 60×60px 以内的小图，一天刷 3~5 次，可以忽略。
 * 用 LruCache 按 (颜色, 形状, 尺寸) 复用 —— 换个月份视图时同一批颜色会反复出现。
 */
object WidgetChip {
    private const val MAX_ENTRIES = 64
    private val cache = LruCache<String, Bitmap>(MAX_ENTRIES)

    /** 色条：完全圆头（与 App 里 `pillOf(6)` 同款）。 */
    fun bar(color: Int, wPx: Int, hPx: Int): Bitmap =
        rounded(color, wPx, hPx, radiusPx = wPx / 2f)

    /** 胶囊：圆角为高度的一半。 */
    fun pill(color: Int, wPx: Int, hPx: Int): Bitmap =
        rounded(color, wPx, hPx, radiusPx = hPx / 2f)

    /** 圆点：中卡行首那个，直径 = 高。 */
    fun circle(color: Int, sizePx: Int): Bitmap = rounded(
        color, sizePx, sizePx, radiusPx = sizePx / 2f,
    )

    private fun rounded(color: Int, w: Int, h: Int, radiusPx: Float): Bitmap {
        val width = w.coerceAtLeast(1)
        val height = h.coerceAtLeast(1)
        val key = "$color:$width:$height:$radiusPx"
        cache.get(key)?.let { return it }

        val bmp = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color }
        // 圆角半径不能超过短边的一半，否则 RectF 会画出怪形状。
        val r = radiusPx.coerceAtMost(minOf(width, height) / 2f)
        canvas.drawRoundRect(RectF(0f, 0f, width.toFloat(), height.toFloat()), r, r, paint)
        cache.put(key, bmp)
        return bmp
    }
}
