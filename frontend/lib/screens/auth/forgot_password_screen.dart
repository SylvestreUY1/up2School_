import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/helpers.dart';
import 'auth_form_theme.dart';

/// Écran de demande de réinitialisation de mot de passe.
///
/// La logique est volontairement séparée de l'écran de connexion
/// pour garder chaque flux d'authentification lisible et maintenable.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendResetEmail() async {
    final l10n = context.l10n;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final email = _emailController.text.trim();
    print('🔐 [ForgotPassword] Tentative d\'envoi d\'email à: $email');

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      print('⏳ [ForgotPassword] Appel de authProvider.resetPassword...');
      await authProvider.resetPassword(email);
      print('✅ [ForgotPassword] authProvider.resetPassword réussi');

      if (mounted) {
        AppHelpers.showSnackBar(
          context,
          l10n.resetEmailSent,
        );
        Navigator.pop(context);
      }
    } catch (e) {
      print('❌ [ForgotPassword] Erreur capturée: $e');
      if (mounted) {
        AppHelpers.showSnackBar(
          context,
          AppHelpers.userFriendlyErrorMessage(
            e,
            fallback:
                'Nous n’avons pas pu envoyer l’email pour le moment. Réessayez.',
          ),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
      print('🔚 [ForgotPassword] Fin de la méthode');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isWideDesktop = MediaQuery.of(context).size.width >= 1100;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.resetPasswordTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isWideDesktop ? 820 : double.infinity,
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 30),
                    Text(
                      l10n.enterYourEmail,
                      style: TextStyle(fontSize: 16, color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 30),
                    TextFormField(
                      controller: _emailController,
                      style: const TextStyle(color: Colors.white),
                      cursorColor: Colors.white,
                      decoration: AuthFormTheme.inputDecoration(
                        label: l10n.email,
                        icon: Icons.email,
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return l10n.enterEmail;
                        }
                        if (!value.contains('@') || !value.contains('.')) {
                          return l10n.invalidEmail;
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 30),
                    SizedBox(
                      height: 50,
                      child: _isLoading
                          ? const Center(
                              child: CircularProgressIndicator(
                                color: Colors.white,
                              ),
                            )
                          : ElevatedButton(
                              onPressed: _sendResetEmail,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2E9366),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                              child: Text(
                                l10n.send,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                    ),
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
