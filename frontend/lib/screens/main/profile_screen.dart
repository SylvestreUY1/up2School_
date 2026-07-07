import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/user.dart';
import '../../providers/auth_provider.dart';
import '../../providers/locale_provider.dart';
import '../../services/backend_api_service.dart';
import 'edit_academic_screen.dart';
import '../../utils/helpers.dart';
import '../../screens/admin/admin_panel.dart';
import '../../screens/auth/login_screen.dart';
import '../../config/app_config.dart';
import '../../l10n/app_localizations.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with WidgetsBindingObserver {
  final BackendApiService _backendApi = BackendApiService();
  late TextEditingController _phoneController;
  bool _isStartingCheckout = false;
  bool _isCheckingSubscription = false;
  String? _pendingTransactionId;

  bool get _isApplePlatform => AppConfig.isApplePlatform;

  bool _useDesktopLayout(BuildContext context) {
    return AppConfig.isDesktop && MediaQuery.of(context).size.width >= 1100;
  }

  @override
  void initState() {
    super.initState();
    _phoneController = TextEditingController();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _phoneController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _pendingTransactionId != null) {
      unawaited(_checkPendingTransaction());
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AuthProvider>(context).currentUser;
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 28.0,
      ),
      body: user == null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(
                    color: Color.fromARGB(255, 255, 255, 255),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.loadingProfile,
                    style: const TextStyle(
                        color: Color.fromARGB(255, 255, 255, 255)),
                  ),
                ],
              ),
            )
          : Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: _useDesktopLayout(context) ? 720 : double.infinity,
                ),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: EdgeInsets.all(
                      _useDesktopLayout(context) ? 20 : 4,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: CircleAvatar(
                            radius: 50,
                            backgroundColor: AppHelpers.getRandomColor(
                              '${user.id}|${user.email}',
                            ),
                            child: Text(
                              AppHelpers.getUserInitial(
                                user.name,
                                user.email,
                              ),
                              style: const TextStyle(
                                fontSize: 40,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.person),
                            title: Text(l10n.fullName),
                            subtitle: Text(user.name ?? l10n.notSpecified),
                          ),
                        ),
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.email),
                            title: Text(l10n.email),
                            subtitle: Text(user.email),
                          ),
                        ),
                        _buildSubscriptionCard(context, user),
                        _buildLanguageCard(context),

                        // Carte des informations académiques
                        _buildAcademicCard(context, user),

                        // Panneau d'administration pour les admins
                        if (user.role == UserRole.admin)
                          Card(
                            child: ListTile(
                              leading: const Icon(
                                Icons.admin_panel_settings,
                                color: Colors.red,
                              ),
                              title: Text(l10n.adminPanel),
                              subtitle: Text(l10n.manageUsersStructures),
                              trailing: const Icon(
                                Icons.arrow_forward_ios,
                                size: 16,
                              ),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const AdminPanelScreen(),
                                  ),
                                );
                              },
                            ),
                          ),

                        // Option changement de mot de passe pour tous les utilisateurs
                        Card(
                          child: ListTile(
                            leading: const Icon(
                              Icons.lock,
                              color: Color(0xFF2E9366),
                            ),
                            title: Text(l10n.changePassword),
                            trailing: const Icon(
                              Icons.arrow_forward_ios,
                              size: 16,
                            ),
                            onTap: () => _showChangePasswordDialog(context),
                          ),
                        ),

                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () => _confirmSignOut(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                            child: Text(l10n.signOut),
                          ),
                        ),
                        const SizedBox(height: 20),

                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () => _showDeleteAccountDialog(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade900,
                              foregroundColor: Colors.white,
                            ),
                            child: Text(l10n.deleteMyAccount),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildSubscriptionCard(BuildContext context, UserModel user) {
    final l10n = context.l10n;
    final isActive = user.isSubscriptionActive;
    final isApplePlatform = _isApplePlatform;
    final subtitle = isActive
        ? l10n.subscriptionActiveUntil(
            _formatSubscriptionDate(context, user.subscriptionEndDate),
          )
        : isApplePlatform
            ? l10n.accessLockedDescription
            : l10n.subscriptionLockedDescription;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isActive ? Icons.verified : Icons.lock_outline,
                  color: isActive ? const Color(0xFF2E9366) : Colors.orange,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isApplePlatform
                            ? l10n.archiveAccess
                            : l10n.yearlySubscription,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(subtitle, style: TextStyle(color: Colors.grey[700])),
                    ],
                  ),
                ),
                Chip(
                  label: Text(
                    isActive ? l10n.enabledLabel : l10n.disabledLabel,
                  ),
                  backgroundColor: isActive
                      ? const Color(0xFFE5F4EC)
                      : const Color(0xFFFFF4E5),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (user.subscriptionSchoolYear != null)
              Text(
                l10n.schoolYearLabel(user.subscriptionSchoolYear!),
                style: TextStyle(color: Colors.grey[700]),
              ),
            if (user.phone != null && user.phone!.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  isApplePlatform
                      ? l10n.phoneLabel(user.phone!)
                      : l10n.paymentNumberLabel(user.phone!),
                  style: TextStyle(color: Colors.grey[700]),
                ),
              ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isCheckingSubscription
                        ? null
                        : () => _refreshSubscription(context),
                    icon: _isCheckingSubscription
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF2E9366),
                            ),
                          )
                        : const Icon(Icons.refresh),
                    label: Text(l10n.refresh),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF2E9366),
                    ),
                  ),
                ),
                if (!isApplePlatform) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: isActive || _isStartingCheckout
                          ? null
                          : () => _startSubscriptionCheckout(context, user),
                      icon: _isStartingCheckout
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.workspace_premium),
                      label: Text(
                        isActive ? l10n.activeStatus : l10n.subscribe,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2E9366),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLanguageCard(BuildContext context) {
    final l10n = context.l10n;
    return Consumer<LocaleProvider>(
      builder: (context, localeProvider, _) => Card(
        child: ListTile(
          leading: const Icon(Icons.translate),
          title: Text(l10n.appLanguage),
          subtitle: Text(l10n.appLanguageDescription),
          trailing: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: localeProvider.locale?.languageCode,
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(l10n.systemDefault),
                ),
                DropdownMenuItem<String?>(
                  value: 'fr',
                  child: Text(l10n.french),
                ),
                DropdownMenuItem<String?>(
                  value: 'en',
                  child: Text(l10n.english),
                ),
              ],
              onChanged: (value) => localeProvider.setLocaleCode(value),
            ),
          ),
        ),
      ),
    );
  }

  String _formatSubscriptionDate(BuildContext context, DateTime? value) {
    if (value == null) return context.l10n.undefinedValue;
    final safe = value.toLocal();
    return '${safe.day.toString().padLeft(2, '0')}/${safe.month.toString().padLeft(2, '0')}/${safe.year}';
  }

  Future<void> _refreshSubscription(BuildContext context) async {
    setState(() {
      _isCheckingSubscription = true;
    });

    try {
      await Provider.of<AuthProvider>(
        context,
        listen: false,
      ).refreshCurrentUser();
      if (mounted) {
        AppHelpers.showSnackBar(
            context, context.l10n.subscriptionStatusUpdated);
      }
    } catch (e) {
      if (mounted) {
        AppHelpers.showSnackBar(
          context,
          context.l10n.subscriptionStatusUpdateFailed,
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingSubscription = false;
        });
      }
    }
  }

  Future<void> _checkPendingTransaction() async {
    final transactionId = _pendingTransactionId;
    if (transactionId == null || _isCheckingSubscription) return;

    setState(() {
      _isCheckingSubscription = true;
    });

    try {
      await _backendApi.checkSubscriptionTransaction(transactionId);
      final refreshed = await Provider.of<AuthProvider>(
        context,
        listen: false,
      ).refreshCurrentUser();
      if (refreshed?.isSubscriptionActive == true) {
        _pendingTransactionId = null;
        if (mounted) {
          AppHelpers.showSnackBar(context, context.l10n.subscriptionActivated);
        }
      }
    } catch (_) {
      // Le webhook peut arriver un peu plus tard; on laisse la verification
      // se refaire au prochain retour dans l'application.
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingSubscription = false;
        });
      }
    }
  }

  Future<void> _startSubscriptionCheckout(
    BuildContext context,
    UserModel user,
  ) async {
    if (_isApplePlatform) {
      return;
    }

    // Initialiser le contrôleur avec le numéro existant
    _phoneController.text = user.phone ?? '';

    final phone = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF307A59), // fond vert foncé
        title: Text(
          context.l10n.paymentNumberPrompt,
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: context.l10n.phone,
            hintText: context.l10n.paymentPhoneExample,
            labelStyle: const TextStyle(color: Colors.white70),
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.7)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.7)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.7)),
            ),
            filled: true,
            fillColor: Colors.white.withOpacity(0.1),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            style: TextButton.styleFrom(foregroundColor: Colors.white70),
            child: Text(context.l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.pop(dialogContext, _phoneController.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF307A59),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(5),
              ),
            ),
            child: Text(context.l10n.continueLabel),
          ),
        ],
      ),
    );

    if (!mounted || phone == null || phone.isEmpty) {
      return;
    }

    setState(() {
      _isStartingCheckout = true;
    });

    try {
      final checkout = await _backendApi.createSubscriptionCheckout(
        phone: phone,
        name: user.name,
      );
      final paymentUrl = checkout['paymentUrl']?.toString() ?? '';
      final transactionId = checkout['transactionId']?.toString();
      if (paymentUrl.isEmpty || transactionId == null) {
        throw Exception(context.l10n.paymentLinkUnavailable);
      }

      _pendingTransactionId = transactionId;

      final launched = await launchUrl(
        Uri.parse(paymentUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        throw Exception(context.l10n.unableToOpenPaymentLink);
      }

      if (mounted) {
        AppHelpers.showSnackBar(
          context,
          context.l10n.confirmPaymentReturn,
        );
      }
    } catch (e) {
      if (mounted) {
        AppHelpers.showSnackBar(
          context,
          AppHelpers.userFriendlyErrorMessage(
            e,
            fallback: context.l10n.paymentLaunchFailed,
          ),
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isStartingCheckout = false;
        });
      }
    }
  }

  Widget _buildAcademicCard(BuildContext context, UserModel user) {
    final l10n = context.l10n;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  l10n.academicInformation,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (user.role == UserRole.student)
                  IconButton(
                    icon: const Icon(Icons.edit, size: 20),
                    onPressed: () => _navigateToEditAcademic(context),
                    tooltip: l10n.modify,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (user.faculty != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(Icons.school, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        user.faculty!,
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
              ),
            if (user.level != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(Icons.grade, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.levelLabel(user.level!),
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
              ),
            if (user.field != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(Icons.category, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        user.field!,
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Text(
              l10n.academicInfoHint,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToEditAcademic(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const EditAcademicScreen()),
    );
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final confirmed = await AppHelpers.showConfirmationDialog(
      context,
      context.l10n.signOut,
      context.l10n.signOutConfirmMessage,
    );
    if (confirmed) {
      try {
        await Provider.of<AuthProvider>(context, listen: false).signOut();
        AppHelpers.showSnackBar(context, context.l10n.signOutSuccess);
        // PLUS BESOIN DE NAVIGATION MANUELLE
      } catch (e) {
        AppHelpers.showSnackBar(
          context,
          AppHelpers.userFriendlyErrorMessage(
            e,
            fallback: context.l10n.signOutFailed,
          ),
          isError: true,
        );
      }
    }
  }

  void _showChangePasswordDialog(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final l10n = context.l10n;
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmController = TextEditingController();

    // Focus nodes pour détecter le focus
    final currentFocus = FocusNode();
    final newFocus = FocusNode();
    final confirmFocus = FocusNode();

    showDialog(
      context: context,
      builder: (context) {
        // ✅ Déclaration des booléens ici (persistants)
        bool obscureCurrent = true;
        bool obscureNew = true;
        bool obscureConfirm = true;

        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF307A59),
              title: Text(
                l10n.changePassword,
                style: TextStyle(color: Colors.white),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Mot de passe actuel
                    TextFormField(
                      controller: currentPasswordController,
                      obscureText: obscureCurrent,
                      focusNode: currentFocus,
                      style: const TextStyle(color: Colors.white),
                      cursorColor: Colors.white,
                      decoration: InputDecoration(
                        labelText: l10n.currentPassword,
                        labelStyle: const TextStyle(color: Colors.white),
                        prefixIcon: const Icon(Icons.lock, color: Colors.white),
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscureCurrent
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: Colors.white.withOpacity(0.7),
                          ),
                          onPressed: () {
                            setState(() {
                              obscureCurrent = !obscureCurrent;
                            });
                          },
                        ),
                        border: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: Colors.white.withOpacity(0.7),
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: Colors.white.withOpacity(0.7),
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: const BorderSide(
                            color: Colors.white,
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        errorBorder: OutlineInputBorder(
                          borderSide: const BorderSide(
                            color: Color.fromARGB(255, 255, 194, 190),
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        focusedErrorBorder: OutlineInputBorder(
                          borderSide: const BorderSide(
                            color: Color.fromARGB(255, 255, 200, 196),
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        errorStyle: const TextStyle(
                          color: Color.fromARGB(255, 255, 162, 155),
                        ),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.1),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Nouveau mot de passe
                    TextFormField(
                      controller: newPasswordController,
                      obscureText: obscureNew,
                      focusNode: newFocus,
                      style: const TextStyle(color: Colors.white),
                      cursorColor: Colors.white,
                      decoration: InputDecoration(
                        labelText: l10n.newPassword,
                        labelStyle: const TextStyle(color: Colors.white),
                        prefixIcon: const Icon(Icons.lock, color: Colors.white),
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscureNew
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: Colors.white.withOpacity(0.7),
                          ),
                          onPressed: () {
                            setState(() {
                              obscureNew = !obscureNew;
                            });
                          },
                        ),
                        border: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: Colors.white.withOpacity(0.7),
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: Colors.white.withOpacity(0.7),
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: const BorderSide(
                            color: Colors.white,
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        errorBorder: OutlineInputBorder(
                          borderSide: const BorderSide(
                            color: Color.fromARGB(255, 255, 194, 190),
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        focusedErrorBorder: OutlineInputBorder(
                          borderSide: const BorderSide(
                            color: Color.fromARGB(255, 255, 200, 196),
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        errorStyle: const TextStyle(
                          color: Color.fromARGB(255, 255, 162, 155),
                        ),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.1),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Confirmation
                    TextFormField(
                      controller: confirmController,
                      obscureText: obscureConfirm,
                      focusNode: confirmFocus,
                      style: const TextStyle(color: Colors.white),
                      cursorColor: Colors.white,
                      decoration: InputDecoration(
                        labelText: l10n.confirmNewPassword,
                        labelStyle: const TextStyle(color: Colors.white),
                        prefixIcon: const Icon(Icons.lock, color: Colors.white),
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscureConfirm
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: Colors.white.withOpacity(0.7),
                          ),
                          onPressed: () {
                            setState(() {
                              obscureConfirm = !obscureConfirm;
                            });
                          },
                        ),
                        border: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: Colors.white.withOpacity(0.7),
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: Colors.white.withOpacity(0.7),
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: const BorderSide(
                            color: Colors.white,
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        errorBorder: OutlineInputBorder(
                          borderSide: const BorderSide(
                            color: Color.fromARGB(255, 255, 194, 190),
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        focusedErrorBorder: OutlineInputBorder(
                          borderSide: const BorderSide(
                            color: Color.fromARGB(255, 255, 200, 196),
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        errorStyle: const TextStyle(
                          color: Color.fromARGB(255, 255, 162, 155),
                        ),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.1),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  child: Text(l10n.cancel),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (newPasswordController.text != confirmController.text) {
                      AppHelpers.showSnackBar(
                        context,
                        l10n.passwordsDoNotMatch,
                        isError: true,
                      );
                      return;
                    }
                    try {
                      await authProvider.changePassword(
                        currentPasswordController.text,
                        newPasswordController.text,
                      );
                      Navigator.pop(context);
                      AppHelpers.showSnackBar(
                        context,
                        l10n.passwordChanged,
                      );
                    } catch (e) {
                      AppHelpers.showSnackBar(
                        context,
                        AppHelpers.userFriendlyErrorMessage(
                          e,
                          fallback: l10n.passwordChangeFailed,
                        ),
                        isError: true,
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E9366),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: Text(l10n.change),
                ),
              ],
            );
          },
        );
      },
    ).then((_) {
      currentFocus.dispose();
      newFocus.dispose();
      confirmFocus.dispose();
    });
  }

  // Méthode de suppression de compte avec confirmation et réauthentification
  void _showDeleteAccountDialog(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final l10n = context.l10n;
    final passwordController = TextEditingController();
    bool obscurePassword = true;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF307A59),
              title: Text(
                l10n.deleteAccount,
                style: TextStyle(color: Colors.white),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.deleteAccountWarning,
                      style: TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: passwordController,
                      obscureText: obscurePassword,
                      style: const TextStyle(color: Colors.white),
                      cursorColor: Colors.white,
                      decoration: InputDecoration(
                        labelText: l10n.password,
                        labelStyle: const TextStyle(color: Colors.white),
                        prefixIcon: const Icon(Icons.lock, color: Colors.white),
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: Colors.white.withOpacity(0.7),
                          ),
                          onPressed: () {
                            setState(() {
                              obscurePassword = !obscurePassword;
                            });
                          },
                        ),
                        border: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: Colors.white.withOpacity(0.7),
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: Colors.white.withOpacity(0.7),
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: const BorderSide(
                            color: Colors.white,
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.1),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  child: Text(l10n.cancel),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (passwordController.text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(l10n.enterYourPassword),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }
                    try {
                      // Réauthentifier d'abord
                      await authProvider.reauthenticate(
                        passwordController.text,
                      );
                      // Puis supprimer le compte
                      await authProvider.deleteAccount();

                      // Fermer le dialogue
                      if (context.mounted) {
                        Navigator.pop(dialogContext);
                      }

                      // Rediriger vers l'écran de connexion (ou d'accueil)
                      if (context.mounted) {
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                const LoginScreen(), // ou HomeScreen
                          ),
                          (route) => false,
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              AppHelpers.userFriendlyErrorMessage(
                                e,
                                fallback: l10n.accountDeletionFailed,
                              ),
                            ),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: Text(l10n.accountDeleteForever),
                ),
              ],
            );
          },
        );
      },
    ).then((_) => passwordController.dispose());
  }
}
