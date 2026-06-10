import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/event.dart';
import '../../models/user.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../widgets/event_card.dart';
import '../../widgets/loading_screen.dart';
import '../../widgets/random_banner.dart';
import '../../widgets/add_event_dialog.dart';
import '../../utils/helpers.dart';
import '../../utils/constants.dart';
import '../../services/local_event_storage.dart';
import '../../services/local_reminder_scheduler.dart';
import '../../config/app_config.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/permissions.dart';

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  static const Duration _recentPastVisibility = Duration(days: 1);
  final ApiService _apiService = ApiService();
  List<Event> _events = [];
  List<Event> _filteredEvents = [];
  List<Widget> _displayItems = [];
  bool _isLoading = true;
  String? _selectedFilter;

  bool _useDesktopLayout(BuildContext context) {
    return AppConfig.isDesktop && MediaQuery.of(context).size.width >= 1100;
  }

  Widget _wrapResponsiveContent(BuildContext context, Widget child) {
    if (!_useDesktopLayout(context)) {
      return child;
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1080),
        child: child,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.currentUser;

    if (user == null) {
      setState(() {
        _events = [];
        _filteredEvents = [];
        _isLoading = false;
        _buildDisplayItems();
      });
      return;
    }

    // 1. Chargement immédiat depuis le cache local (silencieux, sans changer isLoading)
    try {
      final localEvents = await LocalEventStorage().getUpcomingEvents();
      if (localEvents.isNotEmpty && mounted) {
        final localList = localEvents.map((map) => Event.fromMap(map)).toList();
        setState(() {
          _events = localList;
          _filteredEvents = localList;
          // Ne pas toucher à _isLoading ici pour ne pas masquer le loader si réseau lent
        });
        _buildDisplayItems();
      }
    } catch (e) {
      print('Erreur lecture cache: $e');
    }

    // 2. Chargement réseau (comme avant)
    try {
      List<Event> events;

      if (user.role == UserRole.admin) {
        events = await _apiService.getEvents();
      } else if (user.role == UserRole.delegate && user.field != null) {
        events = await _apiService.getEvents(field: user.field);
      } else {
        events = await _apiService.getEvents(
          faculty: user.faculty,
          level: user.level,
          field: user.field,
        );
      }

      final now = DateTime.now();
      final cutoff = now.subtract(const Duration(days: 1));
      events = events.where((e) => e.date.isAfter(cutoff)).toList();

      events.sort((a, b) {
        final aIsFuture = a.date.isAfter(now);
        final bIsFuture = b.date.isAfter(now);
        if (aIsFuture && !bIsFuture) return -1;
        if (!aIsFuture && bIsFuture) return 1;
        if (aIsFuture) return a.date.compareTo(b.date);
        return b.date.compareTo(a.date);
      });

      // Réconcilier le cache local avec la vérité serveur:
      // on supprime les événements futurs qui n'existent plus côté backend.
      await LocalEventStorage().reconcileUpcomingEvents(events);

      // Mise à jour du cache local
      for (final event in events) {
        await LocalEventStorage().insertEvent(event);
        await LocalReminderScheduler().reschedulForEvent(event);
      }
      await LocalEventStorage().deleteExpiredEvents();

      // Recharger depuis le cache local pour être sûr d'avoir la dernière version
      final updatedLocalEvents = await LocalEventStorage().getUpcomingEvents();
      final updatedList = updatedLocalEvents
          .map((map) => Event.fromMap(map))
          .toList()
        ..sort(_compareEventsForDisplay);

      if (mounted) {
        setState(() {
          _events = updatedList;
          _filteredEvents = updatedList;
          _isLoading = false;
        });
        _buildDisplayItems();
      }
    } catch (e) {
      print('⚠️  Erreur chargement événements: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _buildDisplayItems();
        });
      }
    }
  }

  void _applyFilter(String? filter) {
    setState(() {
      _selectedFilter = filter;

      if (filter == null || filter.isEmpty) {
        _filteredEvents = _events;
      } else {
        _filteredEvents = _events.where((event) {
          if (filter == 'today') {
            final now = DateTime.now();
            final today = DateTime(now.year, now.month, now.day);
            final eventDay =
                DateTime(event.date.year, event.date.month, event.date.day);
            return eventDay == today;
          } else if (filter == 'week') {
            final now = DateTime.now();
            final weekLater = now.add(const Duration(days: 7));
            return event.date.isAfter(now) && event.date.isBefore(weekLater);
          } else if (filter == 'month') {
            final now = DateTime.now();
            final monthLater = now.add(const Duration(days: 30));
            return event.date.isAfter(now) && event.date.isBefore(monthLater);
          }
          return true;
        }).toList();
      }
    });
    _filteredEvents.sort(_compareEventsForDisplay);
    _buildDisplayItems();
  }

  bool _isRecentlyPast(Event event) {
    final now = DateTime.now();
    final cutoff = now.subtract(_recentPastVisibility);
    return event.date.isBefore(now) && event.date.isAfter(cutoff);
  }

  int _compareEventsForDisplay(Event a, Event b) {
    final now = DateTime.now();
    final aIsPast = a.date.isBefore(now);
    final bIsPast = b.date.isBefore(now);

    if (aIsPast != bIsPast) {
      return aIsPast ? 1 : -1;
    }

    if (aIsPast) {
      return b.date.compareTo(a.date);
    }

    return a.date.compareTo(b.date);
  }

  void _buildDisplayItems() {
    final events = _filteredEvents;
    final user = Provider.of<AuthProvider>(context, listen: false).currentUser;
    final l10n = context.l10n;
    final List<Widget> items = [];

    if (events.isEmpty) {
      items.add(
        Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.event_busy, size: 60, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                l10n.noEventsToDisplay,
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
      items.add(
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 0.0),
        ),
      );
    } else {
      for (int i = 0; i < events.length; i++) {
        items.add(EventCard(
          event: events[i],
          isPastEvent: _isRecentlyPast(events[i]),
          onDelete: () => _deleteEvent(events[i]),
          canDelete: Permissions.canDeleteEvent(user, events[i]),
        ));

        if ((i + 1) % 5 == 0) {
          items.add(
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 0.0),
            ),
          );
        }
      }

      if (events.length < 5) {
        items.add(
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 0.0),
          ),
        );
      }
    }

    if (mounted) {
      setState(() {
        _displayItems = items;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    if (authProvider.currentUser == null) {
      return _buildNotLoggedIn();
    }

    if (_isLoading) {
      return const LoadingScreen();
    }

    return _events.isEmpty
        ? _buildEmptyState(authProvider)
        : _buildEventsList(authProvider);
  }

  Widget _buildNotLoggedIn() {
    final l10n = context.l10n;
    return Scaffold(
      body: _wrapResponsiveContent(
        context,
        Padding(
          padding: const EdgeInsets.only(top: 200),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                const Icon(Icons.event_busy, size: 100, color: Colors.grey),
                const SizedBox(height: 20),
                Text(
                  l10n.signInToViewEvents,
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(AuthProvider authProvider) {
    final l10n = context.l10n;
    return Scaffold(
      body: _wrapResponsiveContent(
        context,
        SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height,
            ),
            child: Column(
              children: [
                const RandomBanner(),
                if (authProvider.currentUser?.role == UserRole.delegate ||
                    authProvider.currentUser?.role == UserRole.admin)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: ElevatedButton.icon(
                      onPressed: _showAddEventDialog,
                      icon: const Icon(Icons.add),
                      label: Text(l10n.addEvent),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppConstants.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                      ),
                    ),
                  ),
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.6,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.event_note,
                            size: 100, color: Colors.grey),
                        const SizedBox(height: 20),
                        Text(
                          authProvider.currentUser!.role == UserRole.delegate
                              ? l10n.noEventsInYourField
                              : l10n.noScheduledEvents,
                          style:
                              const TextStyle(fontSize: 18, color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEventsList(AuthProvider authProvider) {
    final user = authProvider.currentUser!;
    final l10n = context.l10n;

    return Scaffold(
      backgroundColor: AppConstants.backgroundColor,
      body: SafeArea(
        child: _wrapResponsiveContent(
          context,
          Column(
            children: [
              // Section de filtres
              Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.events,
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white),
                    ),
                    const SizedBox(height: 12),
                    // Filtres rapides
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildFilterChip(l10n.all, null),
                          const SizedBox(width: 8),
                          _buildFilterChip(l10n.today, 'today'),
                          const SizedBox(width: 8),
                          _buildFilterChip(l10n.thisWeek, 'week'),
                          const SizedBox(width: 8),
                          _buildFilterChip(l10n.thisMonth, 'month'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Bouton d'ajout
              if (user.role == UserRole.delegate || user.role == UserRole.admin)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ElevatedButton.icon(
                    onPressed: _showAddEventDialog,
                    icon: const Icon(Icons.add, color: Colors.white),
                    label: Text(
                      l10n.addEvent,
                      style: TextStyle(color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E9366),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  ),
                ),

              const SizedBox(height: 16),

              // Liste des événements
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _loadEvents,
                  color: const Color(0xFF307A59),
                  child: ListView.builder(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: _displayItems.length,
                    itemBuilder: (context, index) {
                      return _displayItems[index];
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String? value) {
    final isSelected = _selectedFilter == value;

    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        _applyFilter(selected ? value : null);
      },
      backgroundColor: isSelected
          ? AppConstants.primaryColor.withOpacity(0.1)
          : Colors.grey[200],
      selectedColor: AppConstants.primaryColor.withOpacity(0.2),
      checkmarkColor: AppConstants.primaryColor,
      labelStyle: TextStyle(
        color: isSelected ? AppConstants.primaryColor : Colors.grey[700],
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isSelected
              ? AppConstants.primaryColor.withOpacity(0.3)
              : Colors.transparent,
        ),
      ),
    );
  }

  void _showAddEventDialog() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.currentUser!;

    if (user.role == UserRole.delegate && user.field == null) {
      AppHelpers.showSnackBar(context, context.l10n.createEventFieldRequired,
          isError: true);
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AddEventDialog(
        user: user,
        onEventCreated: _loadEvents,
      ),
    );
  }

  Future<void> _deleteEvent(Event event) async {
    final confirmed = await AppHelpers.showConfirmationDialog(
      context,
      context.l10n.deleteEventTitle,
      context.l10n.deleteEventMessage(event.title),
    );

    if (confirmed) {
      try {
        await _apiService.deleteEvent(event.id);
        // SUPPRESSION DU CACHE LOCAL
        await LocalReminderScheduler().cancelForEvent(event);
        await LocalEventStorage().deleteEvent(event.id);
        AppHelpers.showSnackBar(context, context.l10n.eventDeletedSuccess);
        _loadEvents(); // rechargement complet
      } catch (e) {
        AppHelpers.showSnackBar(context, context.l10n.eventDeleteFailed,
            isError: true);
      }
    }
  }
}
