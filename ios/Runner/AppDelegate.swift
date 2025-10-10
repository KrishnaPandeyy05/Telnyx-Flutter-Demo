import Flutter
import UIKit
import PushKit
import CallKit
import AVFoundation
import flutter_callkit_incoming
import WebRTC

@main
@objc class AppDelegate: FlutterAppDelegate, PKPushRegistryDelegate, CallkitIncomingAppDelegate {

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)

        // Setup VOIP push notifications (Telnyx requirement)
        let mainQueue = DispatchQueue.main
        let voipRegistry: PKPushRegistry = PKPushRegistry(queue: mainQueue)
        voipRegistry.delegate = self
        voipRegistry.desiredPushTypes = [PKPushType.voIP]
        
        // CRITICAL: WebRTC audio setup for Telnyx (prevents no-audio bug)
        RTCAudioSession.sharedInstance().useManualAudio = true
        RTCAudioSession.sharedInstance().isAudioEnabled = false
        
        // Setup audio activation method channel
        if let flutterViewController = window?.rootViewController as? FlutterViewController {
            let audioChannel = FlutterMethodChannel(name: "com.adit.callapp/audio", binaryMessenger: flutterViewController.binaryMessenger)
            audioChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
                if call.method == "activateAudio" {
                    print("🔊 Flutter requested audio activation")
                    self?.activateAudioSession()
                    result(true)
                } else if call.method == "deactivateAudio" {
                    print("🔇 Flutter requested audio deactivation")
                    self?.deactivateAudioSession()
                    result(true)
                } else {
                    result(FlutterMethodNotImplemented)
                }
            }
        }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    // Activate WebRTC audio session
    private func activateAudioSession() {
        print("🔊 Activating WebRTC audio session...")
        do {
            let audioSession = AVAudioSession.sharedInstance()
            // Configure for voice with earpiece as default route
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .allowBluetoothA2DP, .allowBluetooth])
            // Prefer the built-in receiver (earpiece) initially
            try audioSession.overrideOutputAudioPort(.none)
            try audioSession.setActive(true)
            
            RTCAudioSession.sharedInstance().audioSessionDidActivate(audioSession)
            RTCAudioSession.sharedInstance().isAudioEnabled = true
            
            print("✅ WebRTC audio session activated")
        } catch {
            print("❌ Failed to activate audio session: \(error)")
        }
    }
    
    // Deactivate WebRTC audio session
    private func deactivateAudioSession() {
        print("🔇 Deactivating WebRTC audio session...")
        do {
            let audioSession = AVAudioSession.sharedInstance()
            RTCAudioSession.sharedInstance().audioSessionDidDeactivate(audioSession)
            RTCAudioSession.sharedInstance().isAudioEnabled = false
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            
            print("✅ WebRTC audio session deactivated")
        } catch {
            print("❌ Failed to deactivate audio session: \(error)")
        }
    }

    // MARK: - PKPushRegistryDelegate

    func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        let deviceToken = pushCredentials.token.map { String(format: "%02.2hhx", $0) }.joined()
        print("VoIP Device Token: \(deviceToken)")
        
        // Register with flutter_callkit_incoming plugin (Telnyx requirement)
        SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP(deviceToken)
        
        // Also send to Flutter for Telnyx SDK registration
        if let flutterViewController = window?.rootViewController as? FlutterViewController {
            let channel = FlutterMethodChannel(name: "com.adit.callapp/voip", binaryMessenger: flutterViewController.binaryMessenger)
            channel.invokeMethod("onVoIPTokenReceived", arguments: deviceToken)
        }
    }

    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
        print("📥 didReceiveIncomingPushWith type=\(type.rawValue) payload=\(payload.dictionaryPayload)")
        guard type == .voIP else { completion(); return }
        
        // Extract Telnyx metadata from payload
        if let metadata = payload.dictionaryPayload["metadata"] as? [String: Any] {
            let callID = (metadata["call_id"] as? String) ?? UUID().uuidString
            let callerName = (metadata["caller_name"] as? String) ?? ""
            let callerNumber = (metadata["caller_number"] as? String) ?? ""
            let voiceSdkId = (metadata["voice_sdk_id"] as? String) ?? ""
            let caller = callerName.isEmpty ? (callerNumber.isEmpty ? "Unknown" : callerNumber) : callerName
            
            print("📞 Telnyx VoIP Push - CallID: \(callID), Caller: \(caller), VoiceSDK: \(voiceSdkId)")
            
            // Create CallKit data using flutter_callkit_incoming plugin (report immediately)
            let id = UUID(uuidString: callID) ?? UUID()
            let data = flutter_callkit_incoming.Data(id: id.uuidString, nameCaller: caller, handle: callerNumber, type: 0)
            data.extra = payload.dictionaryPayload as NSDictionary
            data.normalHandle = 1
            data.uuid = id.uuidString
            data.nameCaller = caller
            
            // Show CallKit incoming screen using plugin (CRITICAL for killed-state wakeup)
            SwiftFlutterCallkitIncomingPlugin.sharedInstance?.showCallkitIncoming(data, fromPushKit: true)
            
            // Immediately call completion to satisfy PushKit timing
            completion()

            // Trigger Flutter handling asynchronously after reporting to CallKit
            if let flutterViewController = window?.rootViewController as? FlutterViewController {
                let channel = FlutterMethodChannel(name: "com.adit.callapp/voip", binaryMessenger: flutterViewController.binaryMessenger)
                print("🔌 Notifying Flutter to reconnect WebSocket for incoming call with voice_sdk_id: \(voiceSdkId)")
                print("📦 Passing full metadata to Flutter: \(metadata)")
                DispatchQueue.main.async { [metadata] in
                    channel.invokeMethod("reconnectForIncomingCall", arguments: metadata)
                }
            }
        } else {
            print("❌ No metadata found in VoIP payload")
            completion()
        }
    }

    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        print("🔄 VoIP token invalidated by APNs")
        SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP("")
    }
    
    // Foreground call restoration (Telnyx requirement)
    override func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        print("➡️ application:continueUserActivity for foreground calls")
        return super.application(application, continue: userActivity, restorationHandler: restorationHandler)
    }

    // MARK: - CallkitIncomingAppDelegate (Telnyx requirement)
    
    func onAccept(_ call: flutter_callkit_incoming.Call, _ action: CXAnswerCallAction) {
        print("📞 CallKit Accept")
        action.fulfill()
    }
    
    func onDecline(_ call: flutter_callkit_incoming.Call, _ action: CXEndCallAction) {
        print("📞 CallKit Decline")
        action.fulfill()
    }
    
    func onEnd(_ call: flutter_callkit_incoming.Call, _ action: CXEndCallAction) {
        print("📞 CallKit End")
        action.fulfill()
    }
    
    func onTimeOut(_ call: flutter_callkit_incoming.Call) {
        print("⏱️ CallKit Timeout")
    }
    
    // CRITICAL: WebRTC audio session handling for Telnyx (prevents no-audio bug)
    func didActivateAudioSession(_ audioSession: AVAudioSession) {
        print("🔊 Activate Audio Session (WebRTC)")
        RTCAudioSession.sharedInstance().audioSessionDidActivate(audioSession)
        RTCAudioSession.sharedInstance().isAudioEnabled = true
        // Ensure initial route stays on receiver unless user toggles speaker
        do {
            try audioSession.overrideOutputAudioPort(.none)
        } catch {
            print("⚠️ Failed to enforce receiver route: \(error)")
        }
    }
    
    func didDeactivateAudioSession(_ audioSession: AVAudioSession) {
        print("🔇 DeActivate Audio Session (WebRTC)")
        RTCAudioSession.sharedInstance().audioSessionDidDeactivate(audioSession)
        RTCAudioSession.sharedInstance().isAudioEnabled = false
    }
}
