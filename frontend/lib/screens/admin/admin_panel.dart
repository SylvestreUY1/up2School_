/**
 * FICHIER : admin_panel.dart
 * RÔLE : C'est le centre de contrôle pour les administrateurs.
 * Il permet de gérer les délégués (ceux qui peuvent envoyer des cours) 
 * et les autres administrateurs. C'est un endroit très protégé.
 */
import 'package:flutter/material.dart';
import '../../models/user.dart';
import '../../services/api_service.dart';
import '../../utils/constants.dart';
import '../../utils/helpers.dart';
import 'admin_management.dart';
import 'delegate_management.dart';
import 'faculty_management.dart';

class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  final ApiService _apiService = ApiService();
  List<UserModel> _delegates = []; // Liste des délégués trouvés
  List<UserModel> _admins = []; // Liste des administrateurs trouvés
  bool _isLoading = true; // Pour afficher un rond de chargement

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
      final delegates = await _apiService.getDelegates();
      final admins = await _apiService.getAdmins();
      if (!mounted) return;
      setState(() {
        _delegates = delegates;
        _admins = admins;
      });
    } catch (e) {
      if (!mounted) return;
      AppHelpers.showSnackBar(context, 'Erreur de chargement: $e',
          isError: true);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
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

  bool _useDesktopLayout(BuildContext context) {
    return MediaQuery.of(context).size.width >= 1100;
  }

  Future<void> _openAdminTool(Widget screen) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => screen),
    );
    if (mounted) {
      await _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.backgroundColor,
      appBar: AppBar(
        title: const Text('Panneau d\'Administration'),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white),
            )
          : Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: _useDesktopLayout(context) ? 900 : double.infinity,
                ),
                child: RefreshIndicator(
                  onRefresh: _loadData,
                  color: AppConstants.primaryColor,
                  child: ListView(
                    padding: EdgeInsets.all(
                      _useDesktopLayout(context) ? 24 : 16,
                    ),
                    children: [
                      _buildOverviewCards(),
                      const SizedBox(height: 16),
                      _buildManagementActions(),
                      const SizedBox(height: 24),
                      _buildSectionTitle('Délégués', Icons.people),
                      const SizedBox(height: 10),
                      _buildUserList(
                        users: _delegates,
                        emptyMessage: 'Aucun délégué pour le moment.',
                        trailingBuilder: (delegate) => IconButton(
                          tooltip: 'Retirer le délégué',
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.red),
                          onPressed: () => _removeDelegate(delegate),
                        ),
                      ),
                      const SizedBox(height: 22),
                      _buildSectionTitle(
                        'Administrateurs',
                        Icons.admin_panel_settings,
                      ),
                      const SizedBox(height: 10),
                      _buildUserList(
                        users: _admins,
                        emptyMessage: 'Aucun administrateur trouvé.',
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildOverviewCards() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cards = [
          _buildStatCard(
              'Délégués', _delegates.length.toString(), Icons.people),
          _buildStatCard(
              'Admins', _admins.length.toString(), Icons.admin_panel_settings),
        ];

        if (constraints.maxWidth >= 620) {
          return Row(
            children: [
              Expanded(child: cards[0]),
              const SizedBox(width: 12),
              Expanded(child: cards[1]),
            ],
          );
        }

        return Column(
          children: [
            cards[0],
            const SizedBox(height: 12),
            cards[1],
          ],
        );
      },
    );
  }

  Widget _buildManagementActions() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final actions = [
          _buildActionCard(
            title: 'Gérer les délégués',
            subtitle: 'Attribuer ou retirer les droits de dépôt',
            icon: Icons.people_alt,
            onTap: () => _openAdminTool(const DelegateManagementScreen()),
          ),
          _buildActionCard(
            title: 'Ajouter un admin',
            subtitle: 'Promouvoir un utilisateur existant',
            icon: Icons.admin_panel_settings,
            onTap: () => _openAdminTool(const AdminManagementScreen()),
          ),
          _buildActionCard(
            title: 'Facultés',
            subtitle: 'Niveaux, filières et unités',
            icon: Icons.school,
            onTap: () => _openAdminTool(const FacultyManagementScreen()),
          ),
        ];

        if (constraints.maxWidth >= 760) {
          return SizedBox(
            height: 150,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: actions[0]),
                const SizedBox(width: 12),
                Expanded(child: actions[1]),
                const SizedBox(width: 12),
                Expanded(child: actions[2]),
              ],
            ),
          );
        }

        return Column(
          children: [
            actions[0],
            const SizedBox(height: 12),
            actions[1],
            const SizedBox(height: 12),
            actions[2],
          ],
        );
      },
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppConstants.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: AppConstants.primaryColor),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppConstants.primaryColor,
                  ),
                ),
                Text(title, style: TextStyle(color: Colors.grey[700])),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppConstants.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: AppConstants.primaryColor),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.grey[700],
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.white, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _buildUserList({
    required List<UserModel> users,
    required String emptyMessage,
    Widget Function(UserModel user)? trailingBuilder,
  }) {
    if (users.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Text(
            emptyMessage,
            style: TextStyle(color: Colors.grey[700]),
          ),
        ),
      );
    }

    return Column(
      children: users.map((user) {
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: AppHelpers.getRandomColor(
                '${user.id}|${user.email}',
              ),
              child: Text(
                AppHelpers.getUserInitial(user.name, user.email),
                style: const TextStyle(color: Colors.white),
              ),
            ),
            title: Text(
              user.name ?? user.email,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              _userSubtitle(user),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: trailingBuilder?.call(user),
          ),
        );
      }).toList(),
    );
  }

  String _userSubtitle(UserModel user) {
    final track = [
      user.faculty,
      user.level,
      user.field,
    ].where((value) => value != null && value.trim().isNotEmpty).join(' • ');

    if (track.isEmpty) {
      return user.email;
    }

    return '${user.email}\n$track';
  }
}
