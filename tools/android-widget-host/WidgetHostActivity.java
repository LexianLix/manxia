package io.manxia.widgetsmoke;

import android.app.Activity;
import android.appwidget.AppWidgetHost;
import android.appwidget.AppWidgetHostView;
import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProviderInfo;
import android.content.ComponentName;
import android.content.SharedPreferences;
import android.graphics.Color;
import android.os.Bundle;
import android.view.Gravity;
import android.widget.FrameLayout;
import android.widget.TextView;

public class WidgetHostActivity extends Activity {
    private AppWidgetHost host;

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        host = new AppWidgetHost(this, 1);
        AppWidgetManager manager = AppWidgetManager.getInstance(this);
        ComponentName provider = new ComponentName("io.manxia.manxia",
            "io.manxia.manxia.ContinueReadingWidget");
        SharedPreferences prefs = getPreferences(MODE_PRIVATE);
        int id = prefs.getInt("id", -1);
        if (id < 0 || manager.getAppWidgetInfo(id) == null) {
            if (id >= 0) host.deleteAppWidgetId(id);
            id = host.allocateAppWidgetId();
            if (!manager.bindAppWidgetIdIfAllowed(id, provider)) {
                host.deleteAppWidgetId(id);
                TextView label = new TextView(this);
                label.setText("Widget binding failed");
                setContentView(label);
                return;
            }
            prefs.edit().putInt("id", id).apply();
        }
        AppWidgetProviderInfo info = manager.getAppWidgetInfo(id);
        AppWidgetHostView widget = host.createView(this, id, info);
        FrameLayout frame = new FrameLayout(this);
        frame.setBackgroundColor(Color.rgb(224, 219, 211));
        frame.addView(widget, new FrameLayout.LayoutParams(dp(300), dp(115), Gravity.CENTER));
        setContentView(frame);
    }

    private int dp(int dp) {
        return Math.round(dp * getResources().getDisplayMetrics().density);
    }

    @Override protected void onStart() {
        super.onStart();
        host.startListening();
    }

    @Override protected void onStop() {
        host.stopListening();
        super.onStop();
    }
}
