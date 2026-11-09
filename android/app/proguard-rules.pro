# SQLCipher usa JNI: no renombrar ni quitar sus clases.
-keep class net.zetetic.** { *; }
-keep class net.sqlcipher.** { *; }
-dontwarn net.sqlcipher.**
# Clases propias llamadas desde el manifiesto / Flutter
-keep class com.riccijandro.agenda_credito.** { *; }
