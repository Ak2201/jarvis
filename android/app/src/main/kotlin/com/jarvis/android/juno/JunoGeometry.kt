package com.jarvis.android.juno

import com.jarvis.android.core.lerp
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

data class Pt(val x: Double, val y: Double)

/**
 * Juno's visor-bot silhouette (JunoShape in the macOS JunoOutfitDrawing.swift): a dome on top (exponent [TOP_EXP]) and a
 * squarer base below ([BOTTOM_EXP]). The engine body, the outfits and every other Juno drawer use these two numbers, so hats
 * and scarves keep hugging the body.
 */
object JunoShape {
    const val TOP_EXP = 2.2
    const val BOTTOM_EXP = 4.5

    /** Point on the outline in direction (ca, sa), screen coordinates (y down). */
    fun point(ca: Double, sa: Double, rx: Double, ry: Double): Pt {
        val e = 2 / (if (sa < 0) TOP_EXP else BOTTOM_EXP)
        val x = rx * (if (ca >= 0) ca.pow(e) else -(-ca).pow(e))
        val y = ry * (if (sa >= 0) sa.pow(e) else -(-sa).pow(e))
        return Pt(x, y)
    }

    /** Radius of the horizontal ring at head-local height y (y up, -1..1). */
    fun ringR(y: Double): Double {
        val a = min(1.0, abs(y))
        val e = if (y > 0) TOP_EXP else BOTTOM_EXP
        return (1 - a.pow(e)).pow(1 / e)
    }

    /** The closed outline as n + 1 points (the last repeats the first). */
    fun points(rx: Double, ry: Double, n: Int = 96): List<Pt> = (0..n).map { i ->
        val a = i.toDouble() / n * PI * 2
        point(cos(a), sin(a), rx, ry)
    }
}

object JunoGeometry {
    const val BODY_SEGMENTS = 72

    /** Ray to rounded-rect boundary intersection, for the mailbox morph (engine.ts rrPoint). */
    fun rrPoint(ca: Double, sa: Double, w: Double, h: Double, cr: Double): Pt {
        val eps = 1e-6
        val kx = if (ca >= 0) 1.0 else -1.0
        val ky = if (sa >= 0) 1.0 else -1.0
        val cx = kx * (w - cr)
        val cy = ky * (h - cr)

        val dot = ca * cx + sa * cy
        val disc = dot * dot - (cx * cx + cy * cy - cr * cr)
        if (disc >= 0) {
            val t = dot + sqrt(disc)
            if (t > eps) {
                val px = ca * t
                val py = sa * t
                if (abs(px) >= w - cr - eps && abs(py) >= h - cr - eps) return Pt(px, py)
            }
        }
        if (abs(sa) > eps) {
            val t = (ky * h) / sa
            if (t > eps) {
                val px = ca * t
                if (abs(px) <= w - cr + eps) return Pt(px, ky * h)
            }
        }
        if (abs(ca) > eps) {
            val t = (kx * w) / ca
            if (t > eps) {
                val py = sa * t
                if (abs(py) <= h - cr + eps) return Pt(kx * w, py)
            }
        }
        return Pt(kx * w, ky * h)
    }

    /** Juno's dome outline ([JunoShape]) blended with the mailbox box by `morph`. */
    fun bodyPoints(rx: Double, ry: Double, r: Double, morph: Double): List<Pt> {
        val tw = r * 1.0
        val th = r * 0.94
        val tr = r * 0.42
        return (0..BODY_SEGMENTS).map { i ->
            val a = i.toDouble() / BODY_SEGMENTS * PI * 2
            val ca = cos(a)
            val sa = sin(a)
            val p0 = JunoShape.point(ca, sa, rx, ry)
            val px0 = p0.x
            val py0 = p0.y
            if (morph >= 0.005) {
                val rr = rrPoint(ca, sa, tw, th, tr)
                Pt(lerp(px0, rr.x, morph), lerp(py0, rr.y, morph))
            } else {
                Pt(px0, py0)
            }
        }
    }
}
