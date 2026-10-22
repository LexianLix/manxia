# Pigeon JNI looks up these Kotlin runtime types by their original names.
# shared_preferences_android 2.5.1 keeps its generated classes, but omits these
# library types. R8 otherwise rewrites suspend-method descriptors, making
# SharedPreferences.getInstance() fail before the first Flutter screen.
# Keep the rest of release shrinking enabled. Flutter loads this file for R8.
# Upstream fix: https://github.com/flutter/packages/pull/13311
# Remove when the locked JNI/plugin versions supply these consumer rules.
-keep class kotlin.Unit { *; }
-keep class kotlin.Result { *; }
-keep class kotlin.Result$Failure { *; }
-keep class kotlin.coroutines.Continuation { *; }
-keep class kotlin.coroutines.intrinsics.CoroutineSingletons { *; }
-keep class kotlin.coroutines.intrinsics.IntrinsicsKt { *; }
