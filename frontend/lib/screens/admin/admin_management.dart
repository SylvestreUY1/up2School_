// admin_management.dart
import 'package:flutter/material.dart';
import '../../models/user.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../utils/helpers.dart';
import '../../widgets/password_confirmation_dialog.dart'; // <-- à ajouter

class AdminManagementScreen extends StatefulWidget {
  const AdminManagementScreen({super.key});

  @override
  State<AdminManagementScreen> createState() => _AdminManagementScreenState();
}

class _AdminManagementScreenState extends State<AdminManagementScreen> {
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();
  final TextEditingController _searchController = TextEditingController();
  List<UserModel> _allUsers = [];
  List<UserModel> _filteredUsers = [];
  bool _isLoading = true;

  bool _useDesktopLayout(BuildContext context) {
    return MediaQuery.of(context).size.width >= 1100;
  }

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoading = true);
    try {
      _allUsers = await _apiService.getAllUsers();
      _filterUsers();
    } catch (e) {
      AppHelpers.showSnackBar(context, 'Erreur de chargement: $e',
          isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _filterUsers() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredUsers = _allUsers
          .where((u) => u.role != UserRole.admin)
          .where((u) =>
              u.email.toLowerCase().contains(query) ||
              (u.name?.toLowerCase().contains(query) ?? false))
          .toList();
    });
  }

  Future<bool> _reauthenticateAdmin(String password) async {
    try {
      await _authService.reauthenticate(password);
      return true;
    } catch (e) {
      AppHelpers.showSnackBar(
        context,
        'Mot de passe incorrect',
        isError: true,
      );
      return false;
    }
  }

  Future<void> _promoteToAdmin(UserModel user) async {
    // Utilisation du nouveau dialogue
    final confirmed = await showPasswordConfirmationDialog(
      context: context,
      title: 'Promouvoir administrateur',
      message:
          'Confirmez votre mot de passe pour promouvoir ${user.name ?? user.email}.',
      onConfirm: (password) async {
        return await _reauthenticateAdmin(password);
      },
    );

    if (confirmed != true) return;

    try {
      await _apiService.updateUserRole(user.id, UserRole.admin);
      await _loadUsers();
      AppHelpers.showSnackBar(
        context,
        '${user.name ?? user.email} est maintenant administrateur',
      );
    } catch (e) {
      AppHelpers.showSnackBar(context, 'Erreur: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajouter un administrateur'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: _useDesktopLayout(context) ? 860 : double.infinity,
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.white),
                  cursorColor: Colors.white,
                  decoration: InputDecoration(
                    labelText: 'Rechercher un utilisateur',
                    labelStyle: const TextStyle(color: Colors.white),
                    prefixIcon: const Icon(Icons.search, color: Colors.white),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          BorderSide(color: Colors.white.withOpacity(0.7)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          BorderSide(color: Colors.white.withOpacity(0.7)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          const BorderSide(color: Colors.white, width: 2),
                    ),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.1),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: Colors.white),
                            onPressed: () {
                              _searchController.clear();
                              _filterUsers();
                            },
                          )
                        : null,
                  ),
                  onChanged: (_) => _filterUsers(),
                ),
              ),
              Expanded(
                child: _isLoading
                    ? const Center(
                        child:
                            CircularProgressIndicator(color: Color(0xFF307A59)))
                    : _filteredUsers.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.person_outline,
                                    size: 100, color: Colors.grey),
                                const SizedBox(height: 20),
                                Text(
                                  _searchController.text.isEmpty
                                      ? 'Aucun utilisateur disponible'
                                      : 'Aucun résultat pour "${_searchController.text}"',
                                  style: const TextStyle(
                                      fontSize: 18, color: Colors.grey),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _filteredUsers.length,
                            itemBuilder: (context, index) {
                              final user = _filteredUsers[index];
                              return Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor:
                                        AppHelpers.getRandomColor(user.email),
                                    child: Text(
                                      AppHelpers.getUserInitial(
                                        user.name,
                                        user.email,
                                      ),
                                      style:
                                          const TextStyle(color: Colors.white),
                                    ),
                                  ),
                                  title: Text(user.name ?? user.email),
                                  subtitle: Text(user.email),
                                  trailing: ElevatedButton(
                                    onPressed: () => _promoteToAdmin(user),
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            const Color(0xFF2E9366),
                                        foregroundColor: Colors.white),
                                    child: const Text('Promouvoir'),
                                  ),
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
