package com.daoban.shiftassistantpro

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
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

    /** 圆点：中卡行首那个，直径 = 高。 */
    fun circle(color: Int, sizePx: Int): Bitmap = rounded(
        color, sizePx, sizePx, radiusPx = sizePx / 2f,
    )

    /**
     * 淡染胶囊：14% 底 + 45% 描边，圆角为高度的一半。
     *
     * App 里那三个徽章（「今天」「N 项待办」「已调班」）是同一族配方，见
     * `calendar_screen.dart` 里 `_todayBadge` 附近的注释。小组件这侧颜色是动态的
     * （主色用户可选、已调班跟当天班次色走），静态 `<shape>` 做不到，所以画位图。
     */
    fun tintedChip(color: Int, wPx: Int, hPx: Int): Bitmap {
        val width = wPx.coerceAtLeast(1)
        val height = hPx.coerceAtLeast(1)
        val key = "tint:$color:$width:$height"
        cache.get(key)?.let { return it }

        val bmp = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        val r = height / 2f
        val rect = RectF(0f, 0f, width.toFloat(), height.toFloat())
        val radius = r.coerceAtMost(minOf(width, height) / 2f)

        val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = color
            alpha = 36 // 0x24 ≈ 14%
            style = Paint.Style.FILL
        }
        canvas.drawRoundRect(rect, radius, radius, fill)

        val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = color
            alpha = 115 // 0x73 ≈ 45%
            style = Paint.Style.STROKE
            strokeWidth = height * 0.08f
        }
        val inset = stroke.strokeWidth / 2f
        canvas.drawRoundRect(
            RectF(inset, inset, width - inset, height - inset),
            radius, radius, stroke,
        )
        cache.put(key, bmp)
        return bmp
    }

    /**
     * 圆角实心块（可选一圈描边）。三处用它：月历那一格的「今天」、周条那一列、
     * 今日卡的「今天」药丸 —— 都是「一整块颜色 + 一个圆角」，所以共用一个函数。
     *
     * 为什么它要烤位图、而格子卡底用静态 `<shape>`：**这一块的颜色是用户选的**
     * （主色可选），静态 drawable 做不到。
     *
     * ⚠️ **位图的宽高要贴近控件真实的像素尺寸** —— 宿主是 `fitXY` 拉伸的，
     * 宽高比差得多时圆角会被拉成椭圆。调用点从 `AppWidgetOptions` 现算。
     */
    fun block(
        color: Int,
        w: Int,
        h: Int,
        radiusPx: Float,
        borderColor: Int = 0,
        borderPx: Float = 0f,
    ): Bitmap {
        val width = w.coerceAtLeast(1)
        val height = h.coerceAtLeast(1)
        val key = "blk:$color:$borderColor:$borderPx:$width:$height:$radiusPx"
        cache.get(key)?.let { return it }

        val bmp = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        // 圆角半径不能超过短边的一半，否则 RectF 会画出怪形状（同 `rounded`）。
        val r = radiusPx.coerceAtMost(minOf(width, height) / 2f)
        canvas.drawRoundRect(
            RectF(0f, 0f, width.toFloat(), height.toFloat()), r, r,
            Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color },
        )
        if (borderPx > 0f) {
            val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                this.color = borderColor
                style = Paint.Style.STROKE
                strokeWidth = borderPx
            }
            val inset = borderPx / 2f
            canvas.drawRoundRect(
                RectF(inset, inset, width - inset, height - inset), r, r, stroke,
            )
        }
        cache.put(key, bmp)
        return bmp
    }

    /**
     * **半透明玻璃块** —— 只给月历那格「今天」用。
     *
     * ⚠️ **别拿它替换 [block]**：`block` 是三处共用的（月历「今天」/ 周条的「今天」列 /
     * 今日卡的「今天」药丸），后两处必须保持实心 —— 今日卡那枚药丸是**白字压主色**，
     * 半透明会让白字在浅色主色上读不出来。
     *
     * 配方照 App 那枚选择块（`calendar_lens.dart:313` 的液态档）：
     * **主色 22% → 10% 的对角渐变 + 2dp 实心主色描边**。
     * App 那枚块**自己不带模糊**（模糊在页面背景那一层），所以这不是「够不着的近似」，
     * 是同款 —— 用户 2026-10-15：「尤其是那个半透明块，如果你能实现的话，那基本上
     * 就很好了」。
     */
    fun glassBlock(
        accent: Int,
        w: Int,
        h: Int,
        radiusPx: Float,
        strokePx: Float,
    ): Bitmap {
        val width = w.coerceAtLeast(1)
        val height = h.coerceAtLeast(1)
        val key = "glass:$accent:$strokePx:$width:$height:$radiusPx"
        cache.get(key)?.let { return it }

        val bmp = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        val r = radiusPx.coerceAtMost(minOf(width, height) / 2f)
        val rect = RectF(0f, 0f, width.toFloat(), height.toFloat())

        // 渐变：左上更实、右下更透（与 App 那个 315° 的方向同向）。
        // `Paint.setAlpha` 会**覆盖**颜色自带的 alpha 字节（见 `tintedChip` 那段），
        // 所以这里用 `withAlpha` 明确给出每一端的 alpha，不靠 setAlpha。
        val from = withAlpha(accent, 56)  // ≈ 22%
        val to = withAlpha(accent, 26)    // ≈ 10%
        val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            shader = LinearGradient(
                0f, 0f, width.toFloat(), height.toFloat(), from, to, Shader.TileMode.CLAMP,
            )
        }
        canvas.drawRoundRect(rect, r, r, fill)

        // 描边：**实心主色**（不是半透明那种）—— 可读性全压在这一圈上，
        // 与班次胶囊「14% 淡染 + 45% 描边」是同一族的做法。
        val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = accent
            style = Paint.Style.STROKE
            strokeWidth = strokePx
        }
        val inset = strokePx / 2f
        canvas.drawRoundRect(
            RectF(inset, inset, width - inset, height - inset), r, r, stroke,
        )
        cache.put(key, bmp)
        return bmp
    }

    /** 把 ARGB 里的 alpha 字节换掉（不引 androidx 依赖，就一行）。 */
    private fun withAlpha(color: Int, alpha: Int): Int =
        (color and 0x00FFFFFF) or (alpha shl 24)

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
