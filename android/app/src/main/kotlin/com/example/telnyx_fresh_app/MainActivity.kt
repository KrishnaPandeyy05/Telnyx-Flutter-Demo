package com.example.telnyx_fresh_app

import android.content.Intent
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.telnyx_fresh_app/callkit"
    private val TAG = "MainActivity"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.d(TAG, "MainActivity onCreate called")
        handleCallKitIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        Log.d(TAG, "MainActivity onNewIntent called")
        setIntent(intent)
        handleCallKitIntent(intent)
    }

    private fun handleCallKitIntent(intent: Intent?) {
        val action = intent?.action
        Log.d(TAG, "Handling intent with action: $action")
        
        if (action == "com.hiennv.flutter_callkit_incoming.ACTION_CALL_ACCEPT") {
            Log.d(TAG, "🎯 CallKit Accept intent detected!")
            
            // Extract all extras from the intent
            val extras = intent.extras
            val extrasMap = mutableMapOf<String, Any?>()
            
            if (extras != null) {
                Log.d(TAG, "Processing ${extras.size()} extras from intent")
                for (key in extras.keySet()) {
                    val value = extras.get(key)
                    val flutterCompatibleValue = convertToFlutterCompatible(value)
                    extrasMap[key] = flutterCompatibleValue
                    Log.d(TAG, "📋 Extra: $key = $value (${value?.javaClass?.simpleName}) -> $flutterCompatibleValue")
                }
            } else {
                Log.d(TAG, "⚠️ No extras found in CallKit intent")
            }
            
            // Prepare arguments for Flutter
            val arguments = mapOf(
                "action" to action,
                "extras" to extrasMap
            )
            
            Log.d(TAG, "📤 Preparing to send to Flutter: callkitAcceptLaunched")
            
            // Send to Flutter with proper timing
            sendToFlutter(arguments)
            
        } else if (action == "com.hiennv.flutter_callkit_incoming.ACTION_CALL_DECLINE") {
            Log.d(TAG, "📞 CallKit Decline intent detected!")
            // Handle decline if needed - for now just log it
            
        } else {
            Log.d(TAG, "🏠 Normal app launch (action: $action)")
        }
    }
    
    private fun sendToFlutter(arguments: Map<String, Any?>) {
        flutterEngine?.dartExecutor?.let { dartExecutor ->
            val methodChannel = MethodChannel(dartExecutor.binaryMessenger, CHANNEL)
            
            Log.d(TAG, "📡 Flutter engine ready, setting up method channel")
            
            // Post to main thread with delay to ensure Flutter is ready
            runOnUiThread {
                android.os.Handler(mainLooper).postDelayed({
                    try {
                        Log.d(TAG, "📤 Invoking Flutter method: callkitAcceptLaunched")
                        methodChannel.invokeMethod("callkitAcceptLaunched", arguments)
                        Log.d(TAG, "✅ Method call sent to Flutter successfully")
                    } catch (e: Exception) {
                        Log.e(TAG, "❌ Error sending method call to Flutter: $e")
                    }
                }, 150) // Slightly longer delay for reliability
            }
        } ?: run {
            Log.w(TAG, "⚠️ Flutter engine not ready yet, will retry")
            // Retry after a longer delay if Flutter engine isn't ready
            android.os.Handler(mainLooper).postDelayed({
                sendToFlutter(arguments)
            }, 500)
        }
    }
    
    private fun convertToFlutterCompatible(value: Any?): Any? {
        return when (value) {
            null -> null
            is String, is Int, is Long, is Double, is Float, is Boolean -> value
            is Bundle -> {
                // Convert Bundle to Map
                val bundleMap = mutableMapOf<String, Any?>()
                for (key in value.keySet()) {
                    bundleMap[key] = convertToFlutterCompatible(value.get(key))
                }
                bundleMap
            }
            is ArrayList<*> -> {
                // Convert ArrayList to List
                value.map { convertToFlutterCompatible(it) }
            }
            is Array<*> -> {
                // Convert Array to List
                value.map { convertToFlutterCompatible(it) }
            }
            else -> {
                // For any other complex type, convert to string representation
                Log.w(TAG, "Converting unsupported type ${value.javaClass.simpleName} to String: $value")
                value.toString()
            }
        }
    }
}
