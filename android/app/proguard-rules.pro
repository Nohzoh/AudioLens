# T98: R8/minification keep rules.
#
# Flutter plugins ship their own consumer proguard rules bundled in their
# AARs (auto-applied, no entry needed here). These rules cover the pieces
# added directly in build.gradle.kts that use reflection or dynamic class
# loading, which R8 can't see through statically.

# ML Kit GenAI (com.google.mlkit:genai-prompt, used by GeminiNanoPlugin.kt)
# and the Play Services location client it depends on — both resolve some
# classes via reflection at runtime.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.** { *; }

# Gson, pulled in transitively by ML Kit GenAI for its request/response
# models — keep field names and generic signatures so reflection-based
# (de)serialization keeps working.
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.gson.** { *; }
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer
