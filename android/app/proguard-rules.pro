# youtubedl-android's own classes are never called (only its files are
# used), and the libraries they need are left out.
-dontwarn com.yausername.**
-dontwarn com.fasterxml.jackson.**
-dontwarn org.apache.commons.**

# rustls-platform-verifier's Kotlin classes are called only from the core
# through JNI.
-keep, includedescriptorclasses class org.rustls.platformverifier.** { *; }
