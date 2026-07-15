# General attributes
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod,InnerClasses
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Google Play Core (deferred components - not used, but referenced by Flutter engine)
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**

# Flutter - Most rules are provided by the Flutter plugin's consumer rules.
# We only keep the essential entry points if they aren't already covered.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.embedding.** { *; }

# Google Play Core / Firebase / Play Services
# These libraries provide their own consumer ProGuard rules.
# We don't need broad keeps unless we see specific issues.

# OkHttp/Okio
# These libraries also provide consumer rules.
# If you use reflection for headers or similar, add specific keeps.

# Crypto libraries (BouncyCastle used by PointyCastle)
-keep class org.bouncycastle.** { *; }
-dontwarn org.bouncycastle.**

# Keep model classes (prevent serialization issues)
# If you use JSON serialization (e.g. json_serializable),
# ensure these classes are kept or annotated.
-keep class **.models.** { *; }
-keep class **.data.** { *; }

# Suppress Java 8 desugaring warnings
-dontwarn j$.util.**

# Flutter Secure Storage
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-keep class androidx.security.crypto.** { *; }
-keep class com.google.crypto.tink.** { *; }
-dontwarn com.google.crypto.tink.**
