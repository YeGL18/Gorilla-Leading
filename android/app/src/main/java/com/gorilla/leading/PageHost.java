package com.gorilla.leading;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Path;
import android.graphics.RectF;
import android.view.View;
import android.widget.FrameLayout;

/** The previous page is real, but must not bleed through the transparent current page. */
final class PageHost extends FrameLayout {
    private View foreground;
    private boolean preview;
    private final Path outline = new Path();

    PageHost(Context context) { super(context); }

    void preview(View page, boolean enabled) {
        foreground = page;
        preview = enabled;
        invalidate();
    }

    @Override protected boolean drawChild(Canvas canvas, View child, long drawingTime) {
        if (!preview || child == foreground || foreground == null) return super.drawChild(canvas, child, drawingTime);
        float sx = foreground.getScaleX(), sy = foreground.getScaleY();
        float left = foreground.getLeft() + foreground.getTranslationX() + foreground.getPivotX() * (1 - sx);
        float top = foreground.getTop() + foreground.getTranslationY() + foreground.getPivotY() * (1 - sy);
        float radius = Ui.dp(getContext(), 28) * Math.min(1, Math.abs(1 - sx) / .06f);
        outline.reset();
        outline.addRoundRect(new RectF(left, top, left + foreground.getWidth() * sx,
                top + foreground.getHeight() * sy), radius, radius, Path.Direction.CW);
        int save = canvas.save();
        canvas.clipOutPath(outline);
        boolean result = super.drawChild(canvas, child, drawingTime);
        canvas.restoreToCount(save);
        return result;
    }
}
