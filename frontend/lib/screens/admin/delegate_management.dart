// delegate_management.dart
import 'package:flutter/material.dart';

import '../../models/user.dart';
import '../../services/api_service.dart';
import '../../utils/helpers.dart';

class DelegateManagementScreen extends StatefulWidget {
  const DelegateManagementScreen({super.key});

  @override
  State<DelegateManagementScreen> createState() =>
      _DelegateManagementScreenState();
}

class _DelegateManagementScreenState extends State<DelegateManagementScreen> {
  final ApiService _apiService = ApiService();
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  List<UserModel> _allUsers = [];
  List<UserModel> _filteredUsers = [];
  List<UserModel> _delegates = [];
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
      final all = await _apiService.getAllUsers();
      final nonAdmins = all.where((u) => u.role != UserRole.admin).toList();

      setState(() {
        _allUsers = nonAdmins;
        _delegates =
            _allUsers.where((u) => u.role == UserRole.delegate).toList();
        _filteredUsers = _allUsers;
        _isLoading = false;
      });
    } catch (e) {
      AppHelpers.showSnackBar(context, 'Erreur de chargement: $e',
          isError: true);
      setState(() => _isLoading = false);
    }
  }

  void _filterUsers() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredUsers = _allUsers.where((user) {
        final email = user.email.toLowerCase();
        final name = (user.name ?? '').toLowerCase();
        return email.contains(query) || name.contains(query);
      }).toList();
    });
  }

  Future<void> _toggleDelegateRole(UserModel user) async {
    final confirmed = await AppHelpers.showConfirmationDialog(
      context,
      'Changer le rôle de délégué',
      user.role == UserRole.delegate
          ? 'Retirer le rôle de délégué à ${user.name ?? user.email} ?'
          : 'Attribuer le rôle de délégué à ${user.name ?? user.email} ?',
    );

    if (!confirmed) return;

    final newRole =
        user.role == UserRole.delegate ? UserRole.student : UserRole.delegate;

    try {
      await _apiService.updateUserRole(user.id, newRole);
      await _loadUsers();
      AppHelpers.showSnackBar(
        context,
        user.role == UserRole.delegate
            ? '${user.name ?? user.email} n\'est plus délégué'
            : '${user.name ?? user.email} est maintenant délégué',
      );
    } catch (e) {
      AppHelpers.showSnackBar(context, 'Erreur: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestion des délégués'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: _useDesktopLayout(context) ? 900 : double.infinity,
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _buildStatCard('Total', _allUsers.length.toString()),
                    const SizedBox(width: 10),
                    _buildStatCard('Délégués', _delegates.length.toString()),
                    const SizedBox(width: 10),
                    _buildStatCard(
                      'Étudiants',
                      (_allUsers.length - _delegates.length).toString(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
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
                                const Icon(Icons.people_outline,
                                    size: 100, color: Colors.grey),
                                const SizedBox(height: 20),
                                Text(
                                  _searchQuery.isEmpty
                                      ? 'Aucun utilisateur trouvé'
                                      : 'Aucun résultat pour "$_searchQuery"',
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
                              return _buildUserCard(user);
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
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
                title,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserCard(UserModel user) {
    final isDelegate = user.role == UserRole.delegate;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppHelpers.getRandomColor(user.email),
          child: Text(
            AppHelpers.getUserInitial(user.name, user.email),
            style: const TextStyle(color: Colors.white),
          ),
        ),
        title: Text(user.name ?? user.email),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(user.email),
            if (user.faculty != null &&
                user.level != null &&
                user.field != null)
              Text('${user.faculty} • ${user.level} • ${user.field}'),
            const SizedBox(height: 4),
            Chip(
              label: Text(
                user.role.label,
                style: TextStyle(
                  color: isDelegate ? Colors.white : Colors.black,
                  fontSize: 12,
                ),
              ),
              backgroundColor:
                  isDelegate ? const Color(0xFF307A59) : Colors.grey[300],
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            ),
          ],
        ),
        trailing: Switch(
          value: isDelegate,
          onChanged: (value) => _toggleDelegateRole(user),
          activeColor: const Color(0xFF307A59),
        ),
      ),
    );
  }
}
