package com.gorilla.leading;

import android.content.Context;
import android.content.res.ColorStateList;
import android.graphics.Typeface;
import android.graphics.drawable.Drawable;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.LayerDrawable;
import android.graphics.drawable.RippleDrawable;
import android.view.Gravity;
import android.widget.Button;

import androidx.core.content.ContextCompat;
import androidx.core.graphics.drawable.DrawableCompat;

import java.text.SimpleDateFormat;
import java.util.Calendar;
import java.util.Date;
import java.util.Locale;

/** Shared control surfaces, readable chat colors and native press feedback. */
final class Ui {
    static final int BG = 0xFFF4F6FA;
    static final int ACCENT = 0xFF246BFD;
    static final int ACCENT_DEEP = 0xFF174DC4;
    static final int INK = 0xFF17202C;
    static final int MUTED = 0xFF667181;
    static final int CARD = 0xFFFFFFFF;
    static final int MINE = 0xFF246BFD;
    static final int MINE_INK = 0xFFFFFFFF;

    private Ui() {}

    static int dp(Context c, float value) {
        return Math.round(value * c.getResources().getDisplayMetrics().density);
    }

    static GradientDrawable round(float radiusPx, int color) {
        GradientDrawable d = new GradientDrawable();
        d.setShape(GradientDrawable.RECTANGLE);
        d.setCornerRadius(radiusPx);
        d.setColor(color);
        return d;
    }

    static GradientDrawable roundStroke(float radiusPx, int fillColor, int strokePx, int strokeColor) {
        GradientDrawable d = round(radiusPx, fillColor);
        d.setStroke(strokePx, strokeColor);
        return d;
    }

    /** 直向漸變圓角底（主頁縮細時露出嚟嘅背景）。 */
    static GradientDrawable gradient(int topColor, int bottomColor, float radiusPx) {
        GradientDrawable d = new GradientDrawable();
        d.setShape(GradientDrawable.RECTANGLE);
        d.setCornerRadius(radiusPx);
        d.setOrientation(GradientDrawable.Orientation.TOP_BOTTOM);
        d.setColors(new int[]{topColor, bottomColor});
        return d;
    }

    /** 對話氣泡：自己嗰邊右下角近直角，對方嗰邊左下角近直角，似 iOS 訊息風格。 */
    static GradientDrawable bubble(float radiusPx, int color, boolean mine) {
        GradientDrawable d = new GradientDrawable();
        d.setColor(color);
        float tail = radiusPx * 0.28f;
        // 圓角次序：左上、右上、右下、左下
        d.setCornerRadii(mine
                ? new float[]{radiusPx, radiusPx, radiusPx, radiusPx, tail, tail, radiusPx, radiusPx}
                : new float[]{radiusPx, radiusPx, radiusPx, radiusPx, radiusPx, radiusPx, tail, tail});
        return d;
    }

    static Drawable ripple(float radiusPx, int color) {
        return new RippleDrawable(ColorStateList.valueOf(0x18246BFD),
                round(radiusPx, color), round(radiusPx, 0xFFFFFFFF));
    }

    static Drawable rippleStroke(float radiusPx, int fillColor, int strokePx, int strokeColor) {
        return new RippleDrawable(ColorStateList.valueOf(0x18246BFD),
                roundStroke(radiusPx, fillColor, strokePx, strokeColor), round(radiusPx, 0xFFFFFFFF));
    }

    /** 玻璃初始化失敗時嘅磨砂膠囊兜底（正常行真折射玻璃，呢個只係保險）。 */
    static Drawable glassFallback(float radiusPx) {
        GradientDrawable base = new GradientDrawable();
        base.setShape(GradientDrawable.RECTANGLE);
        base.setCornerRadius(radiusPx);
        base.setOrientation(GradientDrawable.Orientation.TOP_BOTTOM);
        base.setColors(new int[]{0xEE30343B, 0xF01A1E25});
        base.setStroke(1, 0x30FFFFFF);
        return new LayerDrawable(new Drawable[]{base, glassSheen(radiusPx)});
    }

    /** 磨砂底嘅柔反光（只用喺 fallback 墊底，唔好蓋喺真玻璃上面）。 */
    static Drawable glassSheen(float radiusPx) {
        GradientDrawable sheen = new GradientDrawable();
        sheen.setShape(GradientDrawable.RECTANGLE);
        sheen.setCornerRadius(radiusPx);
        sheen.setOrientation(GradientDrawable.Orientation.TOP_BOTTOM);
        sheen.setColors(new int[]{0x22FFFFFF, 0x08FFFFFF, 0x00FFFFFF});
        sheen.setStroke(Math.max(2, (int) (radiusPx * 0.05)), 0x66FFFFFF);
        return sheen;
    }

    /** 玻璃幼邊：1dp 白色半透明 rim，墊喺真玻璃上面（令邊緣透鏡明顯，但唔好成個白環）。 */
    static Drawable glassRim(float radiusPx) {
        GradientDrawable rim = new GradientDrawable();
        rim.setShape(GradientDrawable.RECTANGLE);
        rim.setCornerRadius(radiusPx);
        rim.setColor(0x00000000);
        rim.setStroke(1, 0x38FFFFFF);
        return rim;
    }

    /** Primary actions use a solid blue, not a platform-applied background tint. */
    static Button primaryButton(Context c, String label) {
        Button b = new Button(c);
        b.setText(label);
        b.setAllCaps(false);
        b.setLetterSpacing(0);
        b.setTextSize(15);
        b.setTypeface(null, Typeface.BOLD);
        b.setTextColor(0xFFFFFFFF);
        b.setGravity(Gravity.CENTER);
        GradientDrawable accent = new GradientDrawable();
        accent.setShape(GradientDrawable.RECTANGLE);
        accent.setCornerRadius(dp(c, 16));
        accent.setOrientation(GradientDrawable.Orientation.TOP_BOTTOM);
        accent.setColors(new int[]{ACCENT, ACCENT});
        b.setBackground(new RippleDrawable(ColorStateList.valueOf(0x33FFFFFF), accent, round(dp(c, 16), 0xFFFFFFFF)));
        b.setBackgroundTintList(null);
        b.setPadding(dp(c, 18), 0, dp(c, 18), 0);
        b.setMinWidth(0);
        b.setMinimumWidth(0);
        b.setMinHeight(dp(c, 52));
        pressFeedback(b);
        return b;
    }

    /** Restrained translucent surfaces for secondary actions. */
    static Button secondaryButton(Context c, String label) {
        Button b = new Button(c);
        b.setText(label);
        b.setAllCaps(false);
        b.setLetterSpacing(0);
        b.setTextSize(15);
        b.setTextColor(INK);
        b.setGravity(Gravity.CENTER);
        b.setBackground(rippleStroke(dp(c, 16), 0xDFFFFFFF, Math.max(1, dp(c, 1)), 0x1517202C));
        b.setBackgroundTintList(null);
        b.setPadding(dp(c, 18), 0, dp(c, 18), 0);
        b.setMinWidth(0);
        b.setMinimumWidth(0);
        b.setMinHeight(dp(c, 52));
        pressFeedback(b);
        return b;
    }

    static void pressFeedback(android.view.View view) {
        view.setOnTouchListener((v, event) -> {
            if (!v.isEnabled()) return false;
            switch (event.getActionMasked()) {
                case android.view.MotionEvent.ACTION_DOWN:
                    v.animate().scaleX(.96f).scaleY(.96f).setDuration(110).start(); break;
                case android.view.MotionEvent.ACTION_UP:
                case android.view.MotionEvent.ACTION_CANCEL:
                    v.animate().scaleX(1).scaleY(1).setDuration(210)
                        .setInterpolator(new android.view.animation.DecelerateInterpolator()).start(); break;
            }
            return false;
        });
    }

    static android.app.AlertDialog showDialog(android.app.AlertDialog.Builder builder, boolean destructive) {
        android.app.AlertDialog dialog = builder.create();
        dialog.setOnShowListener(ignored -> {
            if (dialog.getWindow() != null) dialog.getWindow().setBackgroundDrawable(
                round(dp(dialog.getContext(), 26), CARD));
            for (int which : new int[]{-1, -2, -3}) {
                Button button = dialog.getButton(which);
                if (button != null) {
                    button.setAllCaps(false);
                    button.setTextColor(which == -1 && destructive ? 0xFFD92D3E : which == -2 ? MUTED : ACCENT);
                    pressFeedback(button);
                }
            }
        });
        dialog.show();
        return dialog;
    }

    static Button button(Context c, String label) {
        return secondaryButton(c, label);
    }

    static Drawable icon(Context c, int resId, int color) {
        Drawable d = ContextCompat.getDrawable(c, resId);
        if (d == null) return null;
        d = DrawableCompat.wrap(d.mutate());
        DrawableCompat.setTint(d, color);
        return d;
    }

    /** 相對時間：剛剛 / HH:mm / 昨日 HH:mm / M月d日 / yyyy年M月d日 */
    static String time(double epochSeconds) {
        if (epochSeconds <= 0) return "";
        Date date = new Date((long) (epochSeconds * 1000));
        long nowMs = System.currentTimeMillis();
        if (nowMs >= date.getTime() && nowMs - date.getTime() < 60000) return "剛剛";
        Calendar day = Calendar.getInstance();
        day.setTime(date);
        Calendar today = Calendar.getInstance();
        if (sameDay(day, today)) return fmt("HH:mm", date);
        today.add(Calendar.DAY_OF_YEAR, -1);
        if (sameDay(day, today)) return "昨日 " + fmt("HH:mm", date);
        if (day.get(Calendar.YEAR) == Calendar.getInstance().get(Calendar.YEAR)) return fmt("M月d日", date);
        return fmt("yyyy年M月d日", date);
    }

    private static boolean sameDay(Calendar a, Calendar b) {
        return a.get(Calendar.YEAR) == b.get(Calendar.YEAR)
                && a.get(Calendar.DAY_OF_YEAR) == b.get(Calendar.DAY_OF_YEAR);
    }

    private static String fmt(String pattern, Date date) {
        return new SimpleDateFormat(pattern, Locale.getDefault()).format(date);
    }
}
