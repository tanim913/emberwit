package app.emberwit

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/**
 * Home screen widget with one button: it opens Emberwit on a new chat that
 * starts listening (voice typing). The app lock, when on, still asks first.
 */
class VoiceWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val launch = Intent(context, MainActivity::class.java)
            .setAction(MainActivity.ACTION_VOICE)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val pending = PendingIntent.getActivity(
            context,
            0,
            launch,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val views = RemoteViews(context.packageName, R.layout.voice_widget).apply {
            setOnClickPendingIntent(R.id.voice_widget, pending)
        }
        for (id in ids) manager.updateAppWidget(id, views)
    }
}
