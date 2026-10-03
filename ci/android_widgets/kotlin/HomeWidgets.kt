package com.rashad.money_tracker

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

// Home screen widgets. The app saves ready-made text (home_widget); these
// only show it and open the app on the right screen when tapped.

internal fun openApp(ctx: Context, uri: String, code: Int): PendingIntent {
    val i = Intent(ctx, MainActivity::class.java).apply {
        action = Intent.ACTION_VIEW
        data = Uri.parse(uri)
        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
    }
    return PendingIntent.getActivity(
        ctx, code, i, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
}

internal fun SharedPreferences.s(k: String, d: String = ""): String = getString(k, null) ?: d

class AddExpenseWidget : HomeWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager,
                          appWidgetIds: IntArray, widgetData: SharedPreferences) {
        for (id in appWidgetIds) {
            val v = RemoteViews(context.packageName, R.layout.widget_add)
            v.setTextViewText(R.id.label, widgetData.s("l_add", "Add Expense"))
            v.setOnClickPendingIntent(R.id.root, openApp(context, "ewtracker://add?type=expense", 101))
            v.setOnClickPendingIntent(R.id.voice, openApp(context, "ewtracker://add?type=expense&voice=1", 105))
            appWidgetManager.updateAppWidget(id, v)
        }
    }
}

class NetWorthWidget : HomeWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager,
                          appWidgetIds: IntArray, widgetData: SharedPreferences) {
        for (id in appWidgetIds) {
            val v = RemoteViews(context.packageName, R.layout.widget_networth)
            v.setTextViewText(R.id.title, widgetData.s("l_networth", "Net Worth"))
            v.setTextViewText(R.id.value, widgetData.s("networth_short", "—"))
            v.setTextViewText(R.id.unit, widgetData.s("unit", ""))
            v.setTextViewText(R.id.updated, widgetData.s("updated", "Open the app"))
            v.setOnClickPendingIntent(R.id.root, openApp(context, "ewtracker://open?to=accounts", 102))
            appWidgetManager.updateAppWidget(id, v)
        }
    }
}

class MonthWidget : HomeWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager,
                          appWidgetIds: IntArray, widgetData: SharedPreferences) {
        for (id in appWidgetIds) {
            val v = RemoteViews(context.packageName, R.layout.widget_month)
            val unit = widgetData.s("unit", "")
            v.setTextViewText(R.id.title, widgetData.s("l_month", "This Month"))
            v.setTextViewText(R.id.spentLabel, widgetData.s("l_spent", "Spent"))
            v.setTextViewText(R.id.spent, widgetData.s("spent", "—") + " " + unit)
            v.setTextViewText(R.id.incomeLabel, widgetData.s("l_income", "Income"))
            v.setTextViewText(R.id.income, widgetData.s("income", "—") + " " + unit)
            val pct = widgetData.s("budget_pct", "-1").toIntOrNull() ?: -1
            if (pct >= 0) {
                v.setViewVisibility(R.id.bar, View.VISIBLE)
                v.setViewVisibility(R.id.budget, View.VISIBLE)
                v.setProgressBar(R.id.bar, 100, pct.coerceIn(0, 100), false)
                v.setTextViewText(R.id.budget, widgetData.s("budget", ""))
            } else {
                v.setViewVisibility(R.id.bar, View.GONE)
                v.setViewVisibility(R.id.budget, View.GONE)
            }
            v.setOnClickPendingIntent(R.id.root, openApp(context, "ewtracker://open?to=transactions", 103))
            v.setOnClickPendingIntent(R.id.add, openApp(context, "ewtracker://add?type=expense", 104))
            appWidgetManager.updateAppWidget(id, v)
        }
    }
}

class DueWidget : HomeWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager,
                          appWidgetIds: IntArray, widgetData: SharedPreferences) {
        for (id in appWidgetIds) {
            val v = RemoteViews(context.packageName, R.layout.widget_due)
            v.setTextViewText(R.id.title, widgetData.s("l_due", "Due Soon"))
            v.setTextViewText(R.id.card, widgetData.s("due_title", "—"))
            v.setTextViewText(R.id.cardSub, widgetData.s("due_sub", ""))
            val rec = widgetData.s("recurring", "")
            v.setTextViewText(R.id.recurring, rec)
            v.setViewVisibility(R.id.recurring, if (rec.isEmpty()) View.GONE else View.VISIBLE)
            v.setOnClickPendingIntent(R.id.root, openApp(context, "ewtracker://open?to=due", 105))
            appWidgetManager.updateAppWidget(id, v)
        }
    }
}
