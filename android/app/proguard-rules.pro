# WorkManager & App Startup (Room DB reflection crash fix)
-keep class androidx.work.impl.WorkDatabase** { *; }
-keep class androidx.work.impl.background.** { *; }
-keep class androidx.work.Configuration** { *; }
-keep class androidx.startup.** { *; }
-keep class * extends androidx.room.RoomDatabase { *; }
-dontwarn androidx.work.impl.**
