package io.manxia.manxia

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.util.Base64
import android.view.View
import android.widget.RemoteViews
import java.util.UUID

/** A private projection of the most recent reading record, for the launcher. */
class ContinueReadingWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        render(context, manager, ids)
    }

    companion object {
        const val ACTION_CONTINUE = "io.manxia.manxia.action.CONTINUE_READING"
        private const val EXTRA_TOKEN = "io.manxia.manxia.CONTINUE_TOKEN"
        private const val PREFS = "continue_reading_widget"
        private val keyFormat = Regex("[a-f0-9]{64}")

        private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        fun selectedBook(context: Context, intent: Intent?): String? {
            if (intent?.action != ACTION_CONTINUE) return null
            val state = prefs(context)
            val token = state.getString("token", null) ?: return null
            if (intent.getStringExtra(EXTRA_TOKEN) != token) return null
            return state.getString("book", null)
        }

        fun publish(context: Context, record: Map<*, *>?): Boolean {
            val state = prefs(context)
            val data = record.orEmpty()
            val book = data["book"] as? String
            if (book == null || !keyFormat.matches(book)) {
                if (state.contains("book")) {
                    state.edit().clear().apply()
                    refresh(context)
                }
                return false
            }
            val cover = (data["cover"] as? String)?.takeIf(keyFormat::matches)
            val title = (data["title"] as? String).orEmpty().take(240)
            val chapter = (data["chapter"] as? String).orEmpty().take(240)
            val page = (data["page"] as? Int ?: 0).coerceAtLeast(0)
            val total = (data["total"] as? Int ?: 0).coerceAtLeast(0)
            val switched = state.getString("book", null) != book
            val coverChanged = state.getString("cover", null) != cover
            if (switched || coverChanged || title != state.getString("title", null) ||
                chapter != state.getString("chapter", null) || page != state.getInt("page", 0) ||
                total != state.getInt("total", 0)) {
                val edit = state.edit().putString("book", book).putString("cover", cover)
                    .putString("title", title).putString("chapter", chapter)
                    .putInt("page", page).putInt("total", total)
                if (switched) edit.putString("token", UUID.randomUUID().toString())
                if (switched || coverChanged) edit.remove("coverBytes")
                edit.apply()
                refresh(context)
            }
            return cover != null && !state.contains("coverBytes")
        }

        fun setCover(context: Context, cover: String?, bytes: ByteArray?) {
            val state = prefs(context)
            if (cover == null || bytes == null || bytes.size !in 1..80_000 ||
                cover != state.getString("cover", null)) return
            state.edit().putString("coverBytes", Base64.encodeToString(bytes, Base64.NO_WRAP)).apply()
            refresh(context)
        }

        private fun refresh(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, ContinueReadingWidget::class.java))
            if (ids.isNotEmpty()) render(context, manager, ids)
        }

        private fun render(context: Context, manager: AppWidgetManager, ids: IntArray) {
            val state = prefs(context)
            val active = state.contains("book")
            val views = RemoteViews(context.packageName, R.layout.widget_continue_reading)
            val title = if (active) state.getString("title", "").orEmpty()
                else context.getString(R.string.continue_widget_empty)
            val chapter = state.getString("chapter", "").orEmpty()
            val total = state.getInt("total", 0)
            val page = state.getInt("page", 0).coerceIn(0, total)
            val progress = if (total > 0) context.getString(R.string.continue_widget_pages, page, total) else ""
            val detail = if (active) listOf(chapter, progress).filter { it.isNotBlank() }.joinToString(" · ")
                else context.getString(R.string.continue_widget_open)
            views.setTextViewText(R.id.continue_widget_title, title)
            views.setTextViewText(R.id.continue_widget_detail, detail)
            views.setViewVisibility(R.id.continue_widget_progress, if (active && total > 0) View.VISIBLE else View.GONE)
            if (total > 0) views.setProgressBar(R.id.continue_widget_progress, total, page, false)
            val cover = state.getString("coverBytes", null)?.let {
                val bytes = Base64.decode(it, Base64.NO_WRAP)
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            }
            if (cover != null) views.setImageViewBitmap(R.id.continue_widget_cover, cover)
            else views.setImageViewResource(R.id.continue_widget_cover, R.mipmap.ic_launcher)

            val intent = Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            if (active) {
                intent.action = ACTION_CONTINUE
                intent.putExtra(EXTRA_TOKEN, state.getString("token", null))
            } else {
                intent.action = Intent.ACTION_MAIN
            }
            val pending = PendingIntent.getActivity(context, 0, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            views.setOnClickPendingIntent(R.id.continue_widget_root, pending)
            manager.updateAppWidget(ids, views)
        }
    }
}
