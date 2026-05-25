# WorkManager uses Room internally; R8 must not rename WorkDatabase or its implementations.
-keep class androidx.work.impl.WorkDatabase
-keep class * extends androidx.work.impl.WorkDatabase
-keepnames class androidx.work.impl.WorkDatabase
-keep class * extends androidx.room.RoomDatabase
