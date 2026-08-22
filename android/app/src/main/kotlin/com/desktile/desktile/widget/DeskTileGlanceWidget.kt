package com.desktile.desktile.widget

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.currentState
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import es.antonborri.home_widget.HomeWidgetGlanceState
import es.antonborri.home_widget.HomeWidgetGlanceStateDefinition
import es.antonborri.home_widget.actionStartActivity
import com.desktile.desktile.MainActivity
import org.json.JSONObject

/**
 * Compact course snapshot rendered by the launcher.
 *
 * Flutter writes one JSON string to HomeWidget's shared preferences;
 * defensive parsing keeps a newly-installed widget useful before the first
 * Flutter sync.
 */
class DeskTileGlanceWidget : GlanceAppWidget() {
  override val stateDefinition = HomeWidgetGlanceStateDefinition()

  override suspend fun provideGlance(context: Context, id: GlanceId) {
    provideContent {
      DeskTileContent(context, currentState())
    }
  }
}

@Composable
private fun DeskTileContent(
    context: Context,
    state: HomeWidgetGlanceState,
) {
  val payload = WidgetPayload(state.preferences.getString(PAYLOAD_KEY, null))
  val weekText = if (payload.week > 0) {
    "第${payload.week}周 · ${payload.weekdayLabel}"
  } else {
    payload.weekdayLabel
  }
  val nextText = when {
    payload.nextTitle.isBlank() -> "今天没有课程"
    payload.nextIsCurrent -> "正在上课 · ${payload.nextTitle}"
    else -> payload.nextTitle
  }
  val nextMeta = listOfNotNull(
      payload.nextDayLabel.takeIf { it.isNotBlank() },
      payload.nextTime.takeIf { it.isNotBlank() },
      payload.nextRoom.takeIf { it.isNotBlank() },
  ).joinToString(" · ")

  Column(
      modifier =
          GlanceModifier.fillMaxSize()
              .background(Color(0xFFF7F8FA))
              .padding(14.dp)
              .clickable(onClick = actionStartActivity<MainActivity>(context)),
      verticalAlignment = Alignment.Vertical.Top,
      horizontalAlignment = Alignment.Horizontal.Start,
  ) {
    Text(
        text = "DeskTile",
        style =
            TextStyle(
                color = fixedColor(0xFF3B4656),
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold,
            ),
    )
    Spacer(modifier = GlanceModifier.height(3.dp))
    Text(
        text = weekText,
        style = TextStyle(
            color = fixedColor(0xFF667085),
            fontSize = 12.sp,
        ),
    )
    Spacer(modifier = GlanceModifier.height(8.dp))
    Text(
        text = nextText,
        style = TextStyle(
            color = fixedColor(0xFF17202D),
            fontSize = 19.sp,
            fontWeight = FontWeight.Bold,
        ),
    )
    if (nextMeta.isNotBlank()) {
      Spacer(modifier = GlanceModifier.height(3.dp))
      Text(
          text = nextMeta,
          style = TextStyle(
              color = fixedColor(0xFF667085),
              fontSize = 12.sp,
          ),
      )
    }
    Spacer(modifier = GlanceModifier.height(8.dp))
    Row(modifier = GlanceModifier.fillMaxWidth()) {
      Text(
          text = "今日剩余 ${payload.remainingToday} 节",
          style = TextStyle(
              color = fixedColor(0xFF475467),
              fontSize = 12.sp,
          ),
      )
    }
    if (payload.examTitle.isNotBlank()) {
      Spacer(modifier = GlanceModifier.height(6.dp))
      Text(
          text = "考试 · ${payload.examTitle}",
          style = TextStyle(
              color = fixedColor(0xFFB42318),
              fontSize = 12.sp,
              fontWeight = FontWeight.Bold,
          ),
      )
      val examMeta = listOfNotNull(
          payload.examCountdown.takeIf { it.isNotBlank() },
          payload.examAt.takeIf { it.isNotBlank() },
          payload.examRoom.takeIf { it.isNotBlank() },
      ).joinToString(" · ")
      if (examMeta.isNotBlank()) {
        Text(
            text = examMeta,
            style = TextStyle(
                color = fixedColor(0xFFB42318),
                fontSize = 11.sp,
            ),
        )
      }
    }
  }
}

private const val PAYLOAD_KEY = "desktile_widget_payload"

private fun fixedColor(value: Long) = androidx.glance.color.ColorProvider(
    day = Color(value),
    night = Color(value),
)

private class WidgetPayload(raw: String?) {
  private val json = runCatching { raw?.let(::JSONObject) }.getOrNull()

  val week: Int get() = json?.optInt("week", 0) ?: 0
  val weekdayLabel: String get() = json?.text("weekdayLabel") ?: "学期外"
  val nextTitle: String get() = json?.text("nextTitle") ?: ""
  val nextRoom: String get() = json?.text("nextRoom") ?: ""
  val nextTime: String get() = json?.text("nextTime") ?: ""
  val nextDayLabel: String get() = json?.text("nextDayLabel") ?: ""
  val nextIsCurrent: Boolean get() = json?.optBoolean("nextIsCurrent", false) ?: false
  val remainingToday: Int get() = json?.optInt("remainingToday", 0) ?: 0
  val examTitle: String get() = json?.text("examTitle") ?: ""
  val examAt: String get() = json?.text("examAt") ?: ""
  val examRoom: String get() = json?.text("examRoom") ?: ""
  val examCountdown: String get() = json?.text("examCountdown") ?: ""
}

private fun JSONObject.text(key: String): String {
  val value = optString(key, "")
  return if (value == "null") "" else value
}
