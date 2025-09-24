import Flutter
import UIKit
import PushKit
import CallKit
import AVFoundation
import FirebaseCore

@main
@objc class AppDelegate: FlutterAppDelegate, PKPushRegistryDelegate, CXProviderDelegate {

    private let pushRegistry = PKPushRegistry(queue: nil)
    private var provider: CXProvider?
    private let callController = CXCallController()

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Configure iOS Firebase SDK first - this is REQUIRED
        print("🔥 iOS AppDelegate started - Configuring Firebase...")

        // Debug: Check if GoogleService-Info.plist exists
        if let plistPath = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") {
            print("✅ GoogleService-Info.plist found at: \(plistPath)")
        } else {
            print("❌ GoogleService-Info.plist not found in bundle")
        }

        // Configure Firebase with error handling
        do {
            FirebaseApp.configure()
            print("✅ Firebase configured for iOS")
        } catch {
            print("⚠️ Firebase configuration failed: \(error.localizedDescription)")
            print("🔄 App will continue without Firebase (for development/testing)")
            // Don't crash - let the app continue
        }

        GeneratedPluginRegistrant.register(with: self)

        // Configure CallKit provider
        configureCallKitProvider()

        // Register for VoIP push notifications
        pushRegistry.delegate = self
        pushRegistry.desiredPushTypes = [.voIP]

        // Request microphone permission for VoIP calls
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            if granted {
                print("Microphone permission granted for VoIP")
            } else {
                print("Microphone permission denied for VoIP")
            }
        }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    private func configureCallKitProvider() {
        let configuration = CXProviderConfiguration(localizedName: "Adit Telnyx")
        configuration.maximumCallGroups = 2
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportsVideo = false
        configuration.supportedHandleTypes = [.phoneNumber, .generic]

        // Use default icon or create a simple colored icon
        let iconConfig = UIImage.SymbolConfiguration(pointSize: 40, weight: .medium)
        if let icon = UIImage(systemName: "phone.fill", withConfiguration: iconConfig) {
            configuration.iconTemplateImageData = icon.pngData()
        }

        provider = CXProvider(configuration: configuration)
        provider?.setDelegate(self, queue: nil)
    }

    // MARK: - PKPushRegistryDelegate

    func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        let deviceToken = pushCredentials.token.map { String(format: "%02.2hhx", $0) }.joined()
        print("VoIP Device Token: \(deviceToken)")

        // Send this token to your server for VoIP push notifications
        // You can use Flutter's method channel to send this to Dart side
        if let flutterViewController = window?.rootViewController as? FlutterViewController {
            let channel = FlutterMethodChannel(name: "com.example.telnyx_fresh_app/voip", binaryMessenger: flutterViewController.binaryMessenger)
            channel.invokeMethod("onVoIPTokenReceived", arguments: deviceToken)
        }
    }

    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
        print("Received VoIP push: \(payload.dictionaryPayload)")

        // Handle the incoming VoIP push notification
        handleIncomingVoIPPush(payload: payload, completion: completion)
    }

    private func handleIncomingVoIPPush(payload: PKPushPayload, completion: @escaping () -> Void) {
        print("📱 Handling VoIP push payload: \(payload.dictionaryPayload)")

        // Try different payload structures
        var callData: [String: Any]?

        // Check for nested call_data structure
        if let nestedCallData = payload.dictionaryPayload["call_data"] as? [String: Any] {
            callData = nestedCallData
        }
        // Check for direct payload structure
        else if let directCallData = payload.dictionaryPayload as? [String: Any] {
            callData = directCallData
        }

        guard let data = callData,
              let callId = data["call_id"] as? String,
              let callerName = data["caller_name"] as? String,
              let callerNumber = data["caller_number"] as? String,
              let voiceSdkId = data["voice_sdk_id"] as? String else {
            print("❌ Missing required call data in VoIP payload")
            print("📱 Available keys: \(payload.dictionaryPayload.keys)")
            if let callDataKeys = callData?.keys {
                print("📱 Call data keys: \(Array(callDataKeys))")
            }
            completion()
            return
        }

        // Create a CXCallUpdate to describe the incoming call
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: callerNumber)
        update.localizedCallerName = callerName
        update.hasVideo = false

        // Report the incoming call to CallKit
        provider?.reportNewIncomingCall(with: UUID(uuidString: callId) ?? UUID(), update: update, completion: { error in
            if let error = error {
                print("Error reporting incoming call: \(error.localizedDescription)")
            } else {
                print("Successfully reported incoming call to CallKit")

                // Notify Flutter side about the incoming call
                if let flutterViewController = self.window?.rootViewController as? FlutterViewController {
                    let channel = FlutterMethodChannel(name: "com.example.telnyx_fresh_app/voip", binaryMessenger: flutterViewController.binaryMessenger)
                    channel.invokeMethod("onIncomingCall", arguments: data)
                }
            }
            completion()
        })
    }

    // MARK: - CXProviderDelegate

    func providerDidReset(_ provider: CXProvider) {
        print("CallKit provider did reset")
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        print("CallKit perform answer call: \(action.callUUID)")

        // Configure audio session for call
        configureAudioSessionForCall()

        // Answer the call through the Flutter side
        if let flutterViewController = window?.rootViewController as? FlutterViewController {
            let channel = FlutterMethodChannel(name: "com.example.telnyx_fresh_app/callkit", binaryMessenger: flutterViewController.binaryMessenger)
            channel.invokeMethod("answerCall", arguments: action.callUUID.uuidString)
        }

        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        print("CallKit perform end call: \(action.callUUID)")

        // End the call through the Flutter side
        if let flutterViewController = window?.rootViewController as? FlutterViewController {
            let channel = FlutterMethodChannel(name: "com.example.telnyx_fresh_app/callkit", binaryMessenger: flutterViewController.binaryMessenger)
            channel.invokeMethod("endCall", arguments: action.callUUID.uuidString)
        }

        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        print("CallKit perform start call: \(action.callUUID)")
        action.fulfill()
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        print("CallKit audio session activated")
        configureAudioSessionForCall()
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        print("CallKit audio session deactivated")
    }

    private func configureAudioSessionForCall() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .duckOthers])
            try audioSession.setActive(true)
            print("Audio session configured for call")
        } catch {
            print("Error configuring audio session: \(error.localizedDescription)")
        }
    }

    // Handle when app becomes active
    override func applicationDidBecomeActive(_ application: UIApplication) {
        super.applicationDidBecomeActive(application)

        // Check for any missed calls or pending call state
        if let flutterViewController = window?.rootViewController as? FlutterViewController {
            let channel = FlutterMethodChannel(name: "com.example.telnyx_fresh_app/callkit", binaryMessenger: flutterViewController.binaryMessenger)
            channel.invokeMethod("appDidBecomeActive", arguments: nil)
        }
    }
}
