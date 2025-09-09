import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../../services/credential_storage.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _sipIdController = TextEditingController();
  final _passwordController = TextEditingController();
  final _sipIdFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();

  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _rememberCredentials = true;

  // Animation controllers
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    
    // Setup animations
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    ));
    
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.elasticOut,
    ));
    
    // Start animations
    _fadeController.forward();
    _slideController.forward();
    
    // Check if credentials are already stored
    _checkStoredCredentials();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _sipIdController.dispose();
    _passwordController.dispose();
    _sipIdFocusNode.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  Future<void> _checkStoredCredentials() async {
    final credentialStorage = CredentialStorage();
    final storedCredentials = await credentialStorage.getCredentials();
    
    if (storedCredentials != null) {
      setState(() {
        _sipIdController.text = storedCredentials['sipId'] ?? '';
        _passwordController.text = storedCredentials['password'] ?? '';
      });
    }
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    // Hide keyboard
    FocusScope.of(context).unfocus();

    try {
      // Save credentials if remember is checked
      if (_rememberCredentials) {
        final credentialStorage = CredentialStorage();
        await credentialStorage.saveCredentials(
          sipId: _sipIdController.text.trim(),
          password: _passwordController.text,
        );
      }

      // Add haptic feedback
      HapticFeedback.lightImpact();

      // Simulate network delay for better UX
      await Future.delayed(const Duration(milliseconds: 1500));

      if (mounted) {
        // Navigate to main app
        Navigator.of(context).pushReplacementNamed('/home');
      }
    } catch (error) {
      // Handle login error
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Login failed: ${error.toString()}'),
            backgroundColor: AppTheme.declineRed,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String? _validateSipId(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'SIP ID is required';
    }
    
    // Basic SIP ID validation (should contain @ symbol)
    if (!value.contains('@')) {
      return 'Please enter a valid SIP ID (e.g., user@sip.telnyx.com)';
    }
    
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }
    
    if (value.length < 6) {
      return 'Password must be at least 6 characters';
    }
    
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppTheme.primaryTelnyx,
              AppTheme.primaryTelnyxDark,
              AppTheme.secondaryTelnyx,
            ],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Card(
                    elevation: 8,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildHeader(),
                          const SizedBox(height: 32),
                          _buildLoginForm(),
                          const SizedBox(height: 24),
                          _buildLoginButton(),
                          const SizedBox(height: 16),
                          _buildRememberCheckbox(),
                          const SizedBox(height: 24),
                          _buildFooter(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        // Telnyx Logo placeholder
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: AppTheme.primaryTelnyx,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryTelnyx.withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(
            Icons.phone,
            color: Colors.white,
            size: 40,
          ),
        ),
        
        const SizedBox(height: 24),
        
        Text(
          'Welcome to Telnyx',
          style: AppTheme.callNameStyle.copyWith(
            color: AppTheme.primaryTelnyx,
            fontSize: 24,
          ),
        ),
        
        const SizedBox(height: 8),
        
        Text(
          'Enter your SIP credentials to get started',
          style: AppTheme.callStatusStyle.copyWith(
            color: Colors.grey[600],
            fontSize: 14,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildLoginForm() {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          // SIP ID Field
          TextFormField(
            controller: _sipIdController,
            focusNode: _sipIdFocusNode,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            validator: _validateSipId,
            onFieldSubmitted: (_) {
              _passwordFocusNode.requestFocus();
            },
            decoration: InputDecoration(
              labelText: 'SIP ID',
              hintText: 'user@sip.telnyx.com',
              prefixIcon: const Icon(Icons.person_outline),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: AppTheme.primaryTelnyx,
                  width: 2,
                ),
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Password Field
          TextFormField(
            controller: _passwordController,
            focusNode: _passwordFocusNode,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.done,
            validator: _validatePassword,
            onFieldSubmitted: (_) {
              if (_formKey.currentState!.validate()) {
                _handleLogin();
              }
            },
            decoration: InputDecoration(
              labelText: 'Password',
              hintText: 'Enter your password',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  color: Colors.grey[600],
                ),
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: AppTheme.primaryTelnyx,
                  width: 2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handleLogin,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primaryTelnyx,
          foregroundColor: Colors.white,
          elevation: 2,
          shadowColor: AppTheme.primaryTelnyx.withOpacity(0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Text(
                'Sign In',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }

  Widget _buildRememberCheckbox() {
    return Row(
      children: [
        Checkbox(
          value: _rememberCredentials,
          onChanged: (value) {
            setState(() {
              _rememberCredentials = value ?? true;
            });
          },
          activeColor: AppTheme.primaryTelnyx,
        ),
        Expanded(
          child: GestureDetector(
            onTap: () {
              setState(() {
                _rememberCredentials = !_rememberCredentials;
              });
            },
            child: Text(
              'Remember my credentials',
              style: TextStyle(
                color: Colors.grey[700],
                fontSize: 14,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFooter() {
    return Column(
      children: [
        Text(
          'Having trouble signing in?',
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 12,
          ),
        ),
        
        const SizedBox(height: 8),
        
        GestureDetector(
          onTap: () {
            // Open help or contact support
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Contact support: support@telnyx.com'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
          child: Text(
            'Contact Support',
            style: TextStyle(
              color: AppTheme.primaryTelnyx,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
        
        const SizedBox(height: 16),
        
        Text(
          'Powered by Telnyx',
          style: TextStyle(
            color: Colors.grey[500],
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}
