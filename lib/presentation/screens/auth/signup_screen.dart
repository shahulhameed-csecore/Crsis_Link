import 'package:flutter/material.dart';
import '../../../core/theme/design_system.dart';
import '../../widgets/buttons.dart';
import '../../../core/auth/auth_manager.dart';
import 'package:serverpod_auth_email_flutter/serverpod_auth_email_flutter.dart';
import 'package:serverpod_auth_shared_flutter/serverpod_auth_shared_flutter.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameController = TextEditingController();
  final _validationCodeController = TextEditingController();
  
  bool _isLoading = false;
  bool _isVerificationStep = false;
  String? _errorMessage;
  String? _successMessage;

  late final EmailAuthController _authController;

  @override
  void initState() {
    super.initState();
    _authController = EmailAuthController(AuthManager.client.modules.auth);
  }

  Future<void> _handleSignUp() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final success = await _authController.createAccountRequest(
        _usernameController.text.trim(),
        _emailController.text.trim(),
        _passwordController.text,
      );

      if (success) {
        setState(() {
          _isVerificationStep = true;
          _successMessage = 'Account request created! Check the server console for the code.';
        });
      } else {
        setState(() {
          _errorMessage = 'Failed to create account. User might already exist.';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Network error or invalid data provided.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleVerification() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final userInfo = await _authController.validateAccount(
        _emailController.text.trim(),
        _validationCodeController.text.trim(),
      );

      if (userInfo != null) {
        // We verified the email! Now we must actually authenticate to get the token!
        final serverResponse = await AuthManager.client.modules.auth.email.authenticate(
          _emailController.text.trim(),
          _passwordController.text,
        );

        if (serverResponse.success && serverResponse.userInfo != null) {
          final sessionManager = await SessionManager.instance;
          await sessionManager.registerSignedInUser(
            serverResponse.userInfo!,
            serverResponse.keyId!,
            serverResponse.key!,
          );

          if (mounted) {
            Navigator.of(context).pushReplacementNamed('/main');
          }
        } else {
          setState(() {
            _errorMessage = 'Verified, but failed to auto-login. Please login manually.';
          });
        }
      } else {
        setState(() {
          _errorMessage = 'Invalid validation code.';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Network error during verification.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cleanBackground,
      appBar: AppBar(
        title: Text('SIGN UP', style: AppTypography.primaryHeader.copyWith(fontSize: 24)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: AppColors.pitchBlack),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Join Crsis_Link', style: AppTypography.primaryHeader),
            const SizedBox(height: 8),
            Text('Register to access emergency radar and alerts.', style: AppTypography.body),
            const SizedBox(height: 32),
            
            if (!_isVerificationStep) ...[
              TextField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email Address',
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
            ] else ...[
              TextField(
                controller: _validationCodeController,
                decoration: const InputDecoration(
                  labelText: 'Verification Code (Check server console)',
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
            ],
            const SizedBox(height: 16),
            
            if (_errorMessage != null)
              Text(
                _errorMessage!,
                style: const TextStyle(color: AppColors.emergencyRed, fontWeight: FontWeight.bold),
              ),
            if (_successMessage != null)
              Text(
                _successMessage!,
                style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
              ),
              
            const SizedBox(height: 32),
            
            if (_isLoading)
              const Center(child: CircularProgressIndicator(color: AppColors.pitchBlack))
            else if (!_isVerificationStep)
              CapsulePillButton(
                label: 'Create Account',
                onPressed: _handleSignUp,
              )
            else
              CapsulePillButton(
                label: 'Verify & Login',
                onPressed: _handleVerification,
              ),
          ],
        ),
      ),
    );
  }
}
