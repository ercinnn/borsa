import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_colors.dart';
import '../widgets/glass_card.dart';
import '../widgets/gradient_button.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSignUp = false;
  bool _loading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      _showError('E-posta ve şifre gerekli.');
      return;
    }
    setState(() => _loading = true);
    try {
      final auth = Supabase.instance.client.auth;
      if (_isSignUp) {
        final res = await auth.signUp(email: email, password: password);
        if (!mounted) return;
        if (res.session == null) {
          _showMessage(
            'Kayıt oluşturuldu. E-postana gelen bağlantıyla hesabını '
            'onayladıktan sonra giriş yapabilirsin.',
          );
        }
      } else {
        await auth.signInWithPassword(email: email, password: password);
      }
    } on AuthException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('Beklenmeyen hata: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _loading = true);
    try {
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: Uri.base.toString(),
      );
    } on AuthException catch (e) {
      _showError(e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(color: AppColors.slate950),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: GlassCard(
                glow: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ShaderMask(
                      shaderCallback: (bounds) =>
                          AppColors.bullishGradient.createShader(bounds),
                      child: Text(
                        'BORSA TAKİP',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              color: Colors.white,
                              letterSpacing: 1.2,
                            ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      style: const TextStyle(color: AppColors.slate100),
                      decoration: const InputDecoration(labelText: 'E-posta'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      style: const TextStyle(color: AppColors.slate100),
                      decoration: const InputDecoration(labelText: 'Şifre'),
                      onSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 20),
                    GradientButton(
                      onPressed: _loading ? null : _submit,
                      loading: _loading,
                      expand: true,
                      label: _isSignUp ? 'Kayıt Ol' : 'Giriş Yap',
                    ),
                    TextButton(
                      onPressed: _loading
                          ? null
                          : () => setState(() => _isSignUp = !_isSignUp),
                      child: Text(
                        _isSignUp
                            ? 'Zaten hesabın var mı? Giriş yap'
                            : 'Hesabın yok mu? Kayıt ol',
                      ),
                    ),
                    // Google OAuth redirectTo mantığı (bkz. _signInWithGoogle)
                    // Uri.base.toString() ile tarayıcı URL'sine dayanıyor;
                    // mobilde anlamsız olduğundan buton sadece web'de gösterilir.
                    if (kIsWeb) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                              child: Divider(
                                  color: AppColors.slate800.withValues(alpha: 0.8))),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Text('veya',
                                style: TextStyle(color: AppColors.slate400)),
                          ),
                          Expanded(
                              child: Divider(
                                  color: AppColors.slate800.withValues(alpha: 0.8))),
                        ],
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _loading ? null : _signInWithGoogle,
                        icon: const Icon(Icons.login),
                        label: const Text('Google ile Giriş Yap'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
