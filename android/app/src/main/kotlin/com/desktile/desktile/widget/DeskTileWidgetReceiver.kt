package com.desktile.desktile.widget

import es.antonborri.home_widget.HomeWidgetGlanceWidgetReceiver

/** Android entry point registered in AndroidManifest.xml. */
class DeskTileWidgetReceiver :
    HomeWidgetGlanceWidgetReceiver<DeskTileGlanceWidget>() {
  override val glanceAppWidget = DeskTileGlanceWidget()
}
