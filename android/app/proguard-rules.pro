# rustls-platform-verifier's Kotlin classes are called only from the core
# through JNI.
-keep, includedescriptorclasses class org.rustls.platformverifier.** { *; }
