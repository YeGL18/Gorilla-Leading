package com.gorilla.leading;

import android.graphics.Canvas;
import android.graphics.LinearGradient;
import android.graphics.Paint;
import android.graphics.PixelFormat;
import android.graphics.PorterDuff;
import android.graphics.PorterDuffXfermode;
import android.graphics.RadialGradient;
import android.graphics.Rect;
import android.graphics.Shader;
import android.graphics.drawable.Drawable;
import android.os.SystemClock;

/**
 * iOS AnimatedBackground 嘅光球背景：淺色漸變底＋三顆大光球慢慢漂，疊加處發光。
 * 參數抄自 GorillaTranslate/Views/AnimatedBackground.swift（LegacyOrbField）：
 * 直徑 450/500/420、blur 100、opacity 0.3、preset 0 顏色 BEBC3F/5CAEB7/0098FF，
 * 位置 = 中心 + 偏移 + sin/cos 漂移（freq／amp／phase 全部照抄）。
 * 用 RadialGradient 近似 blur（全 API 硬件加速都得），plusLighter 用 ADD xfermode 重現。
 * 25fps 限速；start()/stop() 由 Activity onResume/onPause 控制。
 */
final class OrbBackground extends Drawable implements Runnable {
    private static final float[] DIAMETER = {450f, 500f, 420f};
    private static final int[] RGB = {0xBEBC3F, 0x5CAEB7, 0x0098FF};
    private static final float OPACITY = 0.315f; // 0.3 × glowStrength 1.05
    private static final float[] OX = {0.05f, 0.05f, -0.05f};
    private static final float[] OY = {0.10f, 0.05f, 0.02f};
    private static final float[] FX = {0.449f, 0.393f, 0.524f};
    private static final float[] FY = {0.35f, 0.31f, 0.42f};
    private static final float[] AX = {0.45f, 0.35f, 0.40f};
    private static final float[] AY = {0.30f, 0.30f, 0.32f};
    private static final float[] PHASE = {0f, 2.1f, 4.2f};
    private static final long FRAME_MS = 40; // 25fps

    private final Paint bgPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint[] orbPaint = new Paint[3];
    private final float[] orbRadius = new float[3];
    private volatile float t;
    private long t0;
    private boolean running;

    OrbBackground(float density) {
        for (int i = 0; i < 3; i++) {
            float core = DIAMETER[i] * density * 0.5f;
            orbRadius[i] = core * 1.45f; // core + blur 100 嘅視覺範圍
            // 近似 blur 後圓盤嘅亮度剖面：平頂 → 軟邊 → 透明
            float[] profile = {1f, 0.97f, 0.75f, 0.32f, 0f};
            float[] stops = {0f, 0.5f, 0.69f, 0.85f, 1f};
            int[] colors = new int[profile.length];
            for (int k = 0; k < profile.length; k++) {
                colors[k] = (Math.round(profile[k] * OPACITY * 255) << 24) | RGB[i];
            }
            Paint p = new Paint(Paint.ANTI_ALIAS_FLAG);
            p.setShader(new RadialGradient(0, 0, orbRadius[i], colors, stops, Shader.TileMode.CLAMP));
            p.setXfermode(new PorterDuffXfermode(PorterDuff.Mode.ADD)); // plusLighter
            orbPaint[i] = p;
        }
    }

    void start() {
        if (running) return;
        if (t0 == 0) t0 = SystemClock.uptimeMillis();
        running = true;
        scheduleSelf(this, SystemClock.uptimeMillis() + FRAME_MS);
    }

    void stop() {
        running = false;
        unscheduleSelf(this);
    }

    @Override public void run() {
        if (!running) return;
        t = (SystemClock.uptimeMillis() - t0) / 1000f;
        invalidateSelf();
        scheduleSelf(this, SystemClock.uptimeMillis() + FRAME_MS);
    }

    @Override protected void onBoundsChange(Rect bounds) {
        super.onBoundsChange(bounds);
        if (bounds.height() > 0) {
            bgPaint.setShader(new LinearGradient(0, bounds.top, 0, bounds.bottom,
                    0xFFF4F7F8, 0xFFE4EAEC, Shader.TileMode.CLAMP));
        }
    }

    @Override public void draw(Canvas canvas) {
        Rect b = getBounds();
        int w = b.width(), h = b.height();
        if (w <= 0 || h <= 0) return;
        canvas.drawPaint(bgPaint);
        float t = this.t;
        canvas.saveLayer(b.left, b.top, b.right, b.bottom, null);
        for (int i = 0; i < 3; i++) {
            float cx = b.left + w * (0.5f + OX[i]) + (float) Math.sin(t * FX[i] + PHASE[i]) * AX[i] * w;
            float cy = b.top + h * (0.5f + OY[i]) + (float) Math.cos(t * FY[i] + PHASE[i]) * AY[i] * h;
            canvas.save();
            canvas.translate(cx, cy);
            canvas.drawCircle(0, 0, orbRadius[i], orbPaint[i]);
            canvas.restore();
        }
        canvas.restore();
    }

    @Override public void setAlpha(int alpha) {}

    @Override public void setColorFilter(android.graphics.ColorFilter colorFilter) {}

    @SuppressWarnings("deprecation")
    @Override public int getOpacity() {
        return PixelFormat.OPAQUE;
    }
}
