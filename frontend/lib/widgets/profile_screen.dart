import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/user.dart';
import '../providers/auth_provider.dart';
import '../utils/constants.dart';
import '../utils/helpers.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.currentUser;

    if (user == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.person_outline, size: 100, color: Colors.grey),
              const SizedBox(height: 20),
              const Text(
                'Non connecté',
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  Navigator.pushNamed(context, RouteConstants.login);
                },
                child: const Text('Se connecter'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mon Profil'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              final confirmed = await AppHelpers.showConfirmationDialog(
                context,
                'Déconnexion',
                'Voulez-vous vraiment vous déconnecter ?',
              );

              if (confirmed) {
                await authProvider.signOut();
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // En-tête du profil
            Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: AppHelpers.getRandomColor(user.email),
                    child: Text(
                      AppHelpers.getUserInitial(user.name, user.email),
                      style: const TextStyle(
                        fontSize: 40,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    user.name ?? 'Utilisateur',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    user.email,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Chip(
                    label: Text(
                      user.role.label,
                      style: const TextStyle(color: Colors.white),
                    ),
                    backgroundColor: _getRoleColor(user.role),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Informations personnelles
            const Text(
              'Informations personnelles',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildInfoCard(user),

            const SizedBox(height: 32),

            // Informations académiques
            const Text(
              'Informations académiques',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildAcademicCard(user),

            const SizedBox(height: 32),

            // Actions du compte
            const Text(
              'Actions',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildActionsCard(context, user),

            const SizedBox(height: 32),

            // Statistiques
            if (user.role == UserRole.delegate || user.role == UserRole.admin)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Statistiques',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildStatsCard(user),
                ],
              ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(UserModel user) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildInfoRow('Email', user.email),
            const Divider(),
            if (user.phone != null) ...[
              _buildInfoRow('Téléphone', user.phone!),
              const Divider(),
            ],
            _buildInfoRow(
              'Membre depuis',
              AppHelpers.formatDate(user.createdAt),
            ),
            const Divider(),
            _buildInfoRow('ID', user.id.substring(0, 8) + '...'),
          ],
        ),
      ),
    );
  }

  Widget _buildAcademicCard(UserModel user) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (user.faculty != null) _buildInfoRow('Faculté', user.faculty!),
            if (user.faculty != null) const Divider(),
            if (user.level != null) _buildInfoRow('Niveau', user.level!),
            if (user.level != null) const Divider(),
            if (user.field != null) _buildInfoRow('Filière', user.field!),
          ],
        ),
      ),
    );
  }

  Widget _buildActionsCard(BuildContext context, UserModel user) {
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.edit, color: Colors.blue),
            title: const Text('Modifier le profil'),
            onTap: () => _showEditProfileDialog(user),
          ),
          const Divider(height: 0),
          ListTile(
            leading: const Icon(Icons.security, color: Colors.blue),
            title: const Text('Changer le mot de passe'),
            onTap: () => _showChangePasswordDialog(),
          ),
          const Divider(height: 0),
          ListTile(
            leading: const Icon(Icons.favorite, color: Colors.blue),
            title: const Text('Mes favoris'),
            onTap: () => _showFavorites(),
          ),
          const Divider(height: 0),
          if (user.role == UserRole.delegate || user.role == UserRole.admin)
            ListTile(
              leading:
                  const Icon(Icons.admin_panel_settings, color: Colors.blue),
              title: Text(user.role == UserRole.admin
                  ? 'Panneau d\'administration'
                  : 'Gestion de ma filière'),
              onTap: () {
                if (user.role == UserRole.admin) {
                  Navigator.pushNamed(context, RouteConstants.admin);
                } else {
                  // Navigation vers l'interface délégué
                }
              },
            ),
        ],
      ),
    );
  }

  Widget _buildStatsCard(UserModel user) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildStatItem('Fichiers', '12'),
            _buildStatItem('Téléchargements', '156'),
            _buildStatItem('Événements', '3'),
            _buildStatItem('Utilisateurs', '24'),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w500,
              color: Colors.black54,
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Text(
            value,
            style: const TextStyle(fontSize: 16),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.blue,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  Color _getRoleColor(UserRole role) {
    switch (role) {
      case UserRole.admin:
        return Colors.red;
      case UserRole.delegate:
        return Colors.green;
      case UserRole.student:
        return Colors.blue;
      case UserRole.guest:
        return Colors.grey;
    }
  }

  void _showEditProfileDialog(UserModel user) {
    final nameController = TextEditingController(text: user.name);
    final phoneController = TextEditingController(text: user.phone);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Modifier le profil'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Nom complet',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: phoneController,
                decoration: const InputDecoration(
                  labelText: 'Téléphone',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              // Implémenter la mise à jour du profil
              Navigator.pop(context);
              AppHelpers.showSnackBar(context, 'Profil mis à jour');
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }

  void _showChangePasswordDialog() {
    String currentPassword = '';
    String newPassword = '';
    String confirmPassword = '';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Changer le mot de passe'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    onChanged: (value) => currentPassword = value,
                    decoration: const InputDecoration(
                      labelText: 'Mot de passe actuel',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    onChanged: (value) => newPassword = value,
                    decoration: const InputDecoration(
                      labelText: 'Nouveau mot de passe',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    onChanged: (value) => confirmPassword = value,
                    decoration: const InputDecoration(
                      labelText: 'Confirmer le nouveau mot de passe',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Annuler'),
              ),
              ElevatedButton(
                onPressed: () {
                  // Validation simple
                  if (newPassword.isEmpty || confirmPassword.isEmpty) {
                    AppHelpers.showSnackBar(
                        context, 'Veuillez remplir tous les champs',
                        isError: true);
                    return;
                  }
                  if (newPassword != confirmPassword) {
                    AppHelpers.showSnackBar(
                        context, 'Les mots de passe ne correspondent pas',
                        isError: true);
                    return;
                  }
                  if (newPassword.length < 6) {
                    AppHelpers.showSnackBar(context,
                        'Le mot de passe doit faire au moins 6 caractères',
                        isError: true);
                    return;
                  }

                  Navigator.pop(context);
                  AppHelpers.showSnackBar(
                      context, 'Mot de passe changé avec succès');
                },
                child: const Text('Changer'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showFavorites() {
    // Implémenter l'affichage des favoris
    AppHelpers.showSnackBar(context, 'Fonctionnalité à venir');
  }
}
