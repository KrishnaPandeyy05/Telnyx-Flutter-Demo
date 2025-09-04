import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../main.dart';
import '../theme/app_theme.dart';
import '../widgets/incoming_call_overlay.dart';
import '../widgets/static_waveform_widget.dart';

class EnhancedHomeScreen extends StatefulWidget {
  const EnhancedHomeScreen({super.key});

  @override
  State<EnhancedHomeScreen> createState() => _EnhancedHomeScreenState();
}

class _EnhancedHomeScreenState extends State<EnhancedHomeScreen>
    with TickerProviderStateMixin {
  final TextEditingController _phoneController = TextEditingController();
  late AnimationController _cardAnimationController;
  late AnimationController _fabAnimationController;
  late Animation<double> _cardAnimation;
  late Animation<double> _fabAnimation;

  @override
  void initState() {
    super.initState();
    
    // Card entrance animations
    _cardAnimationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    _cardAnimation = CurvedAnimation(
      parent: _cardAnimationController,
      curve: Curves.elasticOut,
    );
    
    // FAB entrance animation
    _fabAnimationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    
    _fabAnimation = CurvedAnimation(
      parent: _fabAnimationController,
      curve: Curves.bounceOut,
    );
    
    // Start animations with delays
    _cardAnimationController.forward();
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _fabAnimationController.forward();
    });
  }

  @override
  void dispose() {
    _cardAnimationController.dispose();
    _fabAnimationController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final telnyxService = context.watch<TelnyxService>();
    
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      body: Stack(
        children: [
          // Main content
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 20),
                  
                  // App header
                  _buildAppHeader(),
                  
                  const SizedBox(height: 32),
                  
                  // Connection status card
                  SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(-1, 0),
                      end: Offset.zero,
                    ).animate(_cardAnimation),
                    child: _buildConnectionCard(telnyxService),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Incoming call banner (if any)
                  if (telnyxService.incomingInvite != null)
                    SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, -1),
                        end: Offset.zero,
                      ).animate(_cardAnimation),
                      child: _buildIncomingCallBanner(telnyxService),
                    ),
                  
                  const SizedBox(height: 24),
                  
                  // Dialer card
                  SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(1, 0),
                      end: Offset.zero,
                    ).animate(_cardAnimation),
                    child: _buildDialerCard(telnyxService),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Quick actions
                  SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 1),
                      end: Offset.zero,
                    ).animate(_cardAnimation),
                    child: _buildQuickActions(telnyxService),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Features showcase
                  _buildFeaturesCard(),
                  
                  const SizedBox(height: 100), // Space for FAB
                ],
              ),
            ),
          ),
          
          // Floating Action Button
          Positioned(
            bottom: 30,
            right: 30,
            child: ScaleTransition(
              scale: _fabAnimation,
              child: _buildFloatingActions(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppHeader() {
    return Row(
      children: [
        // App icon/logo
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: AppTheme.incomingCallGradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(15),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryTelnyx.withOpacity(0.3),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: const Icon(
            Icons.phone,
            color: Colors.white,
            size: 24,
          ),
        ),
        
        const SizedBox(width: 16),
        
        // App title and subtitle
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Adit Telnyx',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onBackground,
                ),
              ),
              Text(
                'Voice & Communication',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onBackground.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ),
        
        // Settings button
        IconButton(
          onPressed: () {
            // TODO: Navigate to settings
            HapticFeedback.lightImpact();
          },
          icon: Icon(
            Icons.settings_outlined,
            color: Theme.of(context).colorScheme.onBackground.withOpacity(0.7),
          ),
        ),
      ],
    );
  }

  Widget _buildConnectionCard(TelnyxService service) {
    return Card(
      elevation: 4,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: service.isConnected
              ? LinearGradient(
                  colors: [
                    AppTheme.acceptGreen.withOpacity(0.1),
                    AppTheme.primaryTelnyx.withOpacity(0.1),
                  ],
                )
              : LinearGradient(
                  colors: [
                    AppTheme.declineRed.withOpacity(0.1),
                    AppTheme.warningOrange.withOpacity(0.1),
                  ],
                ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              // Status indicator
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: service.isConnected ? AppTheme.acceptGreen : AppTheme.declineRed,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: (service.isConnected ? AppTheme.acceptGreen : AppTheme.declineRed)
                          .withOpacity(0.5),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
              
              const SizedBox(width: 16),
              
              // Status text
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      service.isConnected ? 'Connected' : 'Disconnected',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: service.isConnected ? AppTheme.acceptGreen : AppTheme.declineRed,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      service.status,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
              
              // Waveform indicator
              if (service.isConnected)
                const StaticWaveformWidget(
                  barCount: 8,
                  maxHeight: 30,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIncomingCallBanner(TelnyxService service) {
    return Card(
      elevation: 8,
      color: AppTheme.primaryTelnyx,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.phone_in_talk, color: Colors.white, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Incoming Call',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        service.incomingInvite?.callerIdNumber ?? 'Unknown',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: service.acceptCall,
                    icon: const Icon(Icons.call, color: Colors.white),
                    label: const Text('Accept', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.acceptGreen,
                      elevation: 4,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: service.declineCall,
                    icon: const Icon(Icons.call_end, color: Colors.white),
                    label: const Text('Decline', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.declineRed,
                      elevation: 4,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDialerCard(TelnyxService service) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Card title
            Row(
              children: [
                Icon(
                  Icons.dialpad,
                  color: AppTheme.primaryTelnyx,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  'Make a Call',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 20),
            
            // Phone input
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              style: Theme.of(context).textTheme.titleMedium,
              decoration: InputDecoration(
                labelText: 'Phone Number',
                hintText: 'Enter number to call',
                prefixIcon: Icon(
                  Icons.phone,
                  color: AppTheme.primaryTelnyx,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppTheme.primaryTelnyx),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: AppTheme.primaryTelnyx.withOpacity(0.3),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: AppTheme.primaryTelnyx,
                    width: 2,
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Call button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: service.isConnected && !service.isCallInProgress
                    ? () {
                        HapticFeedback.mediumImpact();
                        service.makeCall(_phoneController.text.trim());
                      }
                    : null,
                icon: const Icon(Icons.call, color: Colors.white),
                label: const Text(
                  'Call Now',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.acceptGreen,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  elevation: 4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions(TelnyxService service) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quick Actions',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            
            const SizedBox(height: 16),
            
            Row(
              children: [
                Expanded(
                  child: _QuickActionButton(
                    icon: Icons.notifications_active,
                    label: 'Test CallKit',
                    color: AppTheme.warningOrange,
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      service.testCallKitNotification();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _QuickActionButton(
                    icon: Icons.history,
                    label: 'Call History',
                    color: AppTheme.secondaryTelnyx,
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      // TODO: Navigate to call history
                    },
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            Row(
              children: [
                Expanded(
                  child: _QuickActionButton(
                    icon: Icons.contacts,
                    label: 'Contacts',
                    color: AppTheme.primaryTelnyx,
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      // TODO: Navigate to contacts
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _QuickActionButton(
                    icon: Icons.voicemail,
                    label: 'Voicemail',
                    color: AppTheme.mutedGray,
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      // TODO: Navigate to voicemail
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeaturesCard() {
    return Card(
      elevation: 2,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [
              AppTheme.primaryTelnyx.withOpacity(0.1),
              AppTheme.secondaryTelnyx.withOpacity(0.1),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Adit Telnyx - Voice SDK v3.0.0',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primaryTelnyx,
                ),
              ),
              
              const SizedBox(height: 16),
              
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  _FeatureChip(label: 'HD Voice Calls', icon: Icons.hd),
                  _FeatureChip(label: 'Push Notifications', icon: Icons.notifications),
                  _FeatureChip(label: 'CallKit Integration', icon: Icons.phone_iphone),
                  _FeatureChip(label: 'DTMF Support', icon: Icons.dialpad),
                  _FeatureChip(label: 'Call Quality', icon: Icons.signal_cellular_4_bar),
                  _FeatureChip(label: 'Multi-Platform', icon: Icons.devices),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingActions() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton(
          heroTag: "recent",
          mini: true,
          backgroundColor: AppTheme.secondaryTelnyx,
          onPressed: () {
            HapticFeedback.lightImpact();
            // TODO: Show recent calls
          },
          child: const Icon(Icons.history, color: Colors.white),
        ),
        
        const SizedBox(height: 12),
        
        FloatingActionButton(
          heroTag: "contacts",
          backgroundColor: AppTheme.primaryTelnyx,
          onPressed: () {
            HapticFeedback.lightImpact();
            // TODO: Show contacts
          },
          child: const Icon(Icons.contacts, color: Colors.white),
        ),
      ],
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        elevation: 2,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 24),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  final String label;
  final IconData icon;

  const _FeatureChip({
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(
        icon,
        size: 16,
        color: AppTheme.primaryTelnyx,
      ),
      label: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
      backgroundColor: Colors.white,
      elevation: 1,
    );
  }
}
