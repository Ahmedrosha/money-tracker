# WorkManager (used by home_widget) creates its Room database by reflection.
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class androidx.work.** { *; }
-keep class androidx.room.** { *; }
# Widgets and the home_widget plugin.
-keep class es.antonborri.home_widget.** { *; }
-keep class com.rashad.money_tracker.** { *; }
