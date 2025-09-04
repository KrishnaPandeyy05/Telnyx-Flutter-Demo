import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../main.dart' show TelnyxService, globalCallKitCallInfo;
import '../theme/app_theme.dart';
import '../widgets/call_timer_widget.dart';
import '../widgets/call_control_button.dart';
import '../widgets/audio_waveform_widget.dart';

class EnhancedCallScreen extends StatefulWidget {
  const EnhancedCallScreen({super.key});

  @override
  State<EnhancedCallScreen> createState() => _EnhancedCallScreenState();
}

class _EnhancedCallScreenState extends State<EnhancedCallScreen>
    with TickerProviderStateMixin {
  // Call control states
  bool _isMuted = false;
  bool _isSpeakerOn = false;
  bool _isOnHold = false;
  bool _showKeypad = false;
  
  // Animations
  late AnimationController _backgroundController;
  late AnimationController _controlsController;
  late Animation<double> _backgroundAnimation;
  late Animation<double> _controlsAnimation;
  
  // Call timer
  Timer? _callTimer;
  Duration _callDuration = Duration.zero;

  @override
  void initState() {
    super.initState();
    
    // Background animation for active call gradient
    _backgroundController = AnimationController(
      duration: const Duration(seconds: 10),
      vsync: this,
    )..repeat();
    
    _backgroundAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(_backgroundController);
    
    // Controls slide-up animation
    _controlsController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    _controlsAnimation = CurvedAnimation(
      parent: _controlsController,
      curve: Curves.elasticOut,
    );
    
    // Start animations
    _controlsController.forward();
    
    // Start call timer
    _startCallTimer();
    
    // Set status bar style
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarBrightness: Brightness.dark,
        statusBarIconBrightness: Brightness.light,
      ),
    );
  }

  void _startCallTimer() {
    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _callDuration = Duration(seconds: _callDuration.inSeconds + 1);
      });
    });
  }

  @override
  void dispose() {
    _backgroundController.dispose();
    _controlsController.dispose();
    _callTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final telnyxService = context.watch<TelnyxService>();
    
    return Scaffold(
      body: AnimatedBuilder(
        animation: _backgroundAnimation,
        builder: (context, child) {
          return Container(
            decoration: _getBackgroundDecoration(),
            child: SafeArea(
              child: SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: MediaQuery.of(context).size.height - 
                               MediaQuery.of(context).padding.top - 
                               MediaQuery.of(context).padding.bottom,
                  ),
                  child: IntrinsicHeight(
                    child: Column(
                      children: [
                        // Top section with caller info and timer
                        Expanded(
                          flex: 2,
                          child: _buildCallerSection(telnyxService),
                        ),
                        
                        // Audio waveform visualization
                        Expanded(
                          flex: 1,
                          child: _buildWaveformSection(),
                        ),
                        
                        // Call controls
                        Expanded(
                          flex: 2,
                          child: _buildControlsSection(telnyxService),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  BoxDecoration _getBackgroundDecoration() {
    // Dynamic gradient based on call state
    List<Color> gradientColors;
    
    if (_isOnHold) {
      gradientColors = [
        AppTheme.warningOrange,
        AppTheme.warningOrange.withOpacity(0.7),
      ];
    } else if (_isMuted) {
      gradientColors = [
        AppTheme.mutedGray,
        AppTheme.mutedGray.withOpacity(0.7),
      ];
    } else {
      gradientColors = AppTheme.activeCallGradient;
    }
    
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: gradientColors,
        transform: GradientRotation(_backgroundAnimation.value * 0.5),
      ),
    );
  }

  Widget _buildCallerSection(TelnyxService service) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Back button
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                iconSize: 24,
              ),
              const Spacer(),
              // Minimize button
              IconButton(
                onPressed: () {
                  // TODO: Implement picture-in-picture mode
                },
                icon: const Icon(Icons.minimize, color: Colors.white),
                iconSize: 24,
              ),
            ],
          ),
          
          const SizedBox(height: 20),
          
          // Call status
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              _getCallStatusText(service),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          
          const SizedBox(height: 32),
          
          // Caller avatar
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: CircleAvatar(
              radius: 60,
              backgroundColor: Colors.white.withOpacity(0.2),
              child: Text(
                _getCallerInitials(service),
                style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Caller name
          Text(
            _getCallerDisplayName(service),
            style: AppTheme.callNameStyle,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          
          const SizedBox(height: 16),
          
          // Call timer
          CallTimerWidget(duration: _callDuration),
        ],
      ),
    );
  }

  Widget _buildWaveformSection() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 40),
      child: AudioWaveformWidget(),
    );
  }

  Widget _buildControlsSection(TelnyxService service) {
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).animate(_controlsAnimation),
      child: Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            if (_showKeypad) _buildKeypad(service) else _buildMainControls(service),
            
            const SizedBox(height: 20),
            
            // End call button
            _buildEndCallButton(service),
          ],
        ),
      ),
    );
  }

  Widget _buildMainControls(TelnyxService service) {
    return Column(
      children: [
        // First row of controls
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            CallControlButton(
              icon: _isMuted ? Icons.mic_off : Icons.mic,
              isActive: _isMuted,
              activeColor: AppTheme.mutedGray,
              onPressed: () {
                setState(() => _isMuted = !_isMuted);
                service.toggleMute();
                HapticFeedback.lightImpact();
              },
              label: 'Mute',
            ),
            
            CallControlButton(
              icon: Icons.dialpad,
              isActive: _showKeypad,
              onPressed: () {
                setState(() => _showKeypad = !_showKeypad);
                HapticFeedback.lightImpact();
              },
              label: 'Keypad',
            ),
            
            CallControlButton(
              icon: _isSpeakerOn ? Icons.volume_up : Icons.hearing,
              isActive: _isSpeakerOn,
              activeColor: Colors.blue,
              onPressed: () {
                setState(() => _isSpeakerOn = !_isSpeakerOn);
                service.toggleSpeaker(_isSpeakerOn);
                HapticFeedback.lightImpact();
              },
              label: 'Speaker',
            ),
          ],
        ),
        
        const SizedBox(height: 20),
        
        // Second row of controls
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            CallControlButton(
              icon: Icons.add_call,
              onPressed: () {
                // TODO: Implement add call
                HapticFeedback.lightImpact();
              },
              label: 'Add Call',
            ),
            
            CallControlButton(
              icon: _isOnHold ? Icons.play_arrow : Icons.pause,
              isActive: _isOnHold,
              activeColor: AppTheme.warningOrange,
              onPressed: () {
                setState(() => _isOnHold = !_isOnHold);
                service.toggleHold();
                HapticFeedback.lightImpact();
              },
              label: _isOnHold ? 'Resume' : 'Hold',
            ),
            
            CallControlButton(
              icon: Icons.more_vert,
              onPressed: () {
                _showMoreOptions();
                HapticFeedback.lightImpact();
              },
              label: 'More',
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildKeypad(TelnyxService service) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Keypad',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              IconButton(
                onPressed: () => setState(() => _showKeypad = false),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Keypad grid
          GridView.count(
            shrinkWrap: true,
            crossAxisCount: 3,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.0,
            children: [
              for (final tone in ['1', '2', '3', '4', '5', '6', '7', '8', '9', '*', '0', '#'])
                _KeypadButton(
                  text: tone,
                  onPressed: () {
                    service.sendDTMF(tone);
                    HapticFeedback.selectionClick();
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEndCallButton(TelnyxService service) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.heavyImpact();
        service.endCall();
      },
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: AppTheme.declineRed,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppTheme.declineRed.withOpacity(0.4),
              blurRadius: 20,
              spreadRadius: 4,
            ),
          ],
        ),
        child: const Icon(
          Icons.call_end,
          color: Colors.white,
          size: 32,
        ),
      ),
    );
  }

  void _showMoreOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildMoreOption(Icons.swap_calls, 'Transfer Call'),
              _buildMoreOption(Icons.record_voice_over, 'Start Recording'),
              _buildMoreOption(Icons.message, 'Send Message'),
              _buildMoreOption(Icons.contact_page, 'Add to Contacts'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMoreOption(IconData icon, String title) {
    return ListTile(
      leading: Icon(icon, color: AppTheme.primaryTelnyx),
      title: Text(title),
      onTap: () {
        Navigator.pop(context);
        // TODO: Implement option
      },
    );
  }

  String _getCallStatusText(TelnyxService service) {
    if (_isOnHold) return 'On Hold';
    if (service.isCallInProgress) return 'Connected';
    return 'Connecting...';
  }

  String _getCallerDisplayName(TelnyxService service) {
    // Priority 1: Global CallKit call info (for direct launch)
    if (globalCallKitCallInfo != null) {
      return globalCallKitCallInfo!['caller_name'] ?? 'CallKit Call';
    }
    
    // Priority 2: Active call destination
    if (service.call?.sessionDestinationNumber != null) {
      return service.call!.sessionDestinationNumber;
    }
    
    // Priority 3: Incoming call number
    if (service.incomingInvite?.callerIdNumber != null) {
      return service.incomingInvite!.callerIdNumber!;
    }
    
    return 'Unknown Caller';
  }

  String _getCallerInitials(TelnyxService service) {
    final name = _getCallerDisplayName(service);
    final words = name.split(' ');
    if (words.isEmpty) return '?';
    if (words.length == 1) {
      final firstChar = words[0].isNotEmpty ? words[0][0] : '?';
      return firstChar.toUpperCase();
    }
    return '${words[0][0]}${words[1][0]}'.toUpperCase();
  }
}

class _KeypadButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;

  const _KeypadButton({
    required this.text,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.2),
      borderRadius: BorderRadius.circular(50),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(50),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(50),
            border: Border.all(
              color: Colors.white.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Center(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
