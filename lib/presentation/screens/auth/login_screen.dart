import 'package:flutter/material.dart';
import '../../../core/theme/design_system.dart';
import '../../widgets/buttons.dart';
import 'signup_screen.dart';
import '../../../core/auth/auth_manager.dart';
import 'package:serverpod_auth_email_flutter/serverpod_auth_email_flutter.dart';
import 'package:serverpod_auth_shared_flutter/serverpod_auth_shared_flutter.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  
  late final EmailAuthController _authController;

  @override
  void initState() {
    super.initState();
    _authController = EmailAuthController(AuthManager.client.modules.auth);
  }

  Future<void> _handleLogin() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final serverResponse = await AuthManager.client.modules.auth.email.authenticate(
        _emailController.text.trim(),
        _passwordController.text,
      );

      if (serverResponse.success && serverResponse.userInfo != null) {
        // Register session manually
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
          _errorMessage = serverResponse.failReason?.name ?? 'Invalid email or password.';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Network error: $e';
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
        title: Text('LOGIN', style: AppTypography.primaryHeader.copyWith(fontSize: 24)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 48),
            Text('Welcome Back', style: AppTypography.primaryHeader),
            const SizedBox(height: 8),
            Text('Sign in to access emergency services.', style: AppTypography.body),
            const SizedBox(height: 48),
            
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
            const SizedBox(height: 16),
            
            if (_errorMessage != null)
              Text(
                _errorMessage!,
                style: const TextStyle(color: AppColors.emergencyRed, fontWeight: FontWeight.bold),
              ),
              
            const SizedBox(height: 32),
            
            _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.pitchBlack))
                : CapsulePillButton(
                    label: 'Sign In',
                    onPressed: _handleLogin,
                  ),
                  
            const SizedBox(height: 24),
            TextButton(
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SignUpScreen()));
              },
              child: const Text('Don\'t have an account? Sign Up', style: TextStyle(color: AppColors.pitchBlack)),
            ),
          ],
        ),
      ),
    );
  }
}
