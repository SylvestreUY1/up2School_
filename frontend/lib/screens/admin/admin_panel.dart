/**
 * FICHIER : admin_panel.dart
 * RÔLE : C'est le centre de contrôle pour les administrateurs.
 * Il permet de gérer les délégués (ceux qui peuvent envoyer des cours) 
 * et les autres administrateurs. C'est un endroit très protégé.
 */
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/user.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../utils/helpers.dart';
import '../../widgets/password_confirmation_dialog.dart';
import 'delegate_management.dart';
import 'admin_management.dart';

class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();
  List<UserModel> _delegates = []; // Liste des délégués trouvés
  List<UserModel> _admins = [];    // Liste des administrateurs trouvés
  bool _isLoading = true;          // Pour afficher un rond de chargement
  int _selectedIndex = 0;          // 0 pour l'onglet Délégués, 1 pour Admins

  @override
  void initState() {
    super.initState();
    _loadData(); // On charge les listes dès l'ouverture de l'écran
  }

  /**
   * CHARGEMENT DES DONNÉES
   * On demande au serveur la liste de tous les délégués et admins.
   */
  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      _delegates = await _apiService.getDelegates();
      _admins = await _apiService.getAdmins();
    } catch (e) {
      AppHelpers.showSnackBar(context, 'Erreur de chargement: $e', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /**
   * SUPPRIMER UN DÉLÉGUÉ
   * On lui retire ses droits pour qu'il redevienne un simple étudiant.
   */
  Future<void> _removeDelegate(UserModel delegate) async {
    final confirmed = await AppHelpers.showConfirmationDialog(
      context,
      'Retirer le délégué',
      'Voulez-vous vraiment retirer ${delegate.name ?? delegate.email} du rôle de délégué ?',
    );

    if (!confirmed) return;

    try {
      await _apiService.updateUserRole(delegate.id, UserRole.student);
      await _loadData(); // On rafraîchit la liste
      AppHelpers.showSnackBar(context, 'Délégué retiré avec succès');
    } catch (e) {
      AppHelpers.showSnackBar(context, 'Erreur: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Panneau d\'Administration'),
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator()) 
          : _buildBody(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Délégués'),
          BottomNavigationBarItem(icon: Icon(Icons.admin_panel_settings), label: 'Admins'),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return _selectedIndex == 0 ? _buildDelegatesTab() : _buildAdminsTab();
  }

  Widget _buildDelegatesTab() {
    return ListView.builder(
      itemCount: _delegates.length,
      itemBuilder: (context, index) {
        final delegate = _delegates[index];
        return ListTile(
          title: Text(delegate.name ?? delegate.email),
          subtitle: Text(delegate.faculty ?? 'Pas de faculté'),
          trailing: IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: () => _removeDelegate(delegate),
          ),
        );
      },
    );
  }

  Widget _buildAdminsTab() {
    return ListView.builder(
      itemCount: _admins.length,
      itemBuilder: (context, index) {
        final admin = _admins[index];
        return ListTile(
          title: Text(admin.name ?? admin.email),
          subtitle: const Text('Administrateur'),
        );
      },
    );
  }
}
