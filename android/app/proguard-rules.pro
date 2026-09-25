# Flutter Wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class com.google.firebase.** { *; }

# Keep our native service files and receivers
-keep class com.soulsync.app.** { *; }

# For web socket / socket io
-keep class io.socket.** { *; }
-keep class okhttp3.** { *; }
-keep class okio.** { *; }
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn io.socket.**

# Prevent shrinking of JSON models
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# Ignore Google Play Core library warnings/errors
-dontwarn com.google.android.play.core.**
