# flutter_local_notifications 会把「已排定通知」用 Gson 序列化到 SharedPreferences 缓存。
# R8 混淆会破坏这些模型类 / RuntimeTypeAdapterFactory 的反射，导致读取缓存时抛
# "Missing type parameter"，进而使 cancelAll 崩掉、闹钟永远排不进去。
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-dontwarn com.dexterous.flutterlocalnotifications.**

# Gson 反射需要的通用保留
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
