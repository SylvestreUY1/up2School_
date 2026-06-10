/**
 * FICHIER : paiement_pro_service.dart
 * RÔLE : C'est le module qui s'occupe de l'argent. 
 * Il communique avec "PaiementPro" pour permettre aux étudiants de payer 
 * leur abonnement par Mobile Money (Orange, MTN, Moov, etc.).
 */
import 'package:http/http.dart' as http;
import 'dart:convert';

/**
 * Service pour gérer les paiements.
 * Imaginez que c'est le caissier de l'application.
 */
class PaiementProService {
  final String merchantId; // L'identifiant unique de notre boutique Up2School

  // Toutes les infos nécessaires pour un paiement
  late String _amount;              // Le prix à payer
  late String _description;         // Ce qu'on achète (ex: "Abonnement Annuel")
  late String _channel;             // Le moyen de paiement (OM, MTN, etc.)
  late String _countryCurrencyCode; // Le code de la monnaie (952 pour le FCFA)
  late String _referenceNumber;     // Un numéro unique pour suivre cette vente
  late String _customerEmail;       // L'email de l'étudiant
  late String _customerFirstName;   // Son prénom
  late String _customerLastname;    // Son nom
  late String _customerPhoneNumber; // Son numéro de téléphone
  late String _notificationURL;     // L'adresse que PaiementPro appellera pour dire "C'est payé !"
  late String _returnURL;           // L'endroit où l'étudiant revient après avoir payé
  late String _returnContext;

  // Résultats de l'opération
  String? _paymentUrl; // Le lien web où l'étudiant doit aller pour valider son paiement
  String? _message;    // Un message en cas d'erreur
  bool _success = false;

  // Getters (pour lire les résultats depuis l'extérieur)
  String? get paymentUrl => _paymentUrl;
  String? get message => _message;
  bool get success => _success;

  PaiementProService({required this.merchantId});

  /**
   * PRÉPARATION DU PAIEMENT
   * On remplit le "bon de commande" avec toutes les infos de l'étudiant.
   */
  void configurePaiement({
    required int amount,
    required String description,
    required String channel,
    required String referenceNumber,
    required String customerEmail,
    required String customerFirstName,
    required String customerLastname,
    required String customerPhoneNumber,
    required String notificationURL,
    required String returnURL,
    String returnContext = '',
    String countryCurrencyCode = '952', // FCFA par défaut
  }) {
    _amount = amount.toString();
    _description = description;
    _channel = channel;
    _countryCurrencyCode = countryCurrencyCode;
    _referenceNumber = referenceNumber;
    _customerEmail = customerEmail;
    _customerFirstName = customerFirstName;
    _customerLastname = customerLastname;
    _customerPhoneNumber = customerPhoneNumber;
    _notificationURL = notificationURL;
    _returnURL = returnURL;
    _returnContext = returnContext;
  }

  /**
   * LANCER LA TRANSACTION
   * On envoie les infos au serveur de paiement. Si tout est bon, 
   * il nous renvoie un lien (URL) que l'application va ouvrir.
   */
  Future<bool> initierPaiement() async {
    try {
      final url = Uri.https(
        'paiementpro.net',
        '/webservice/onlinepayment/init/curl-init.php',
      );

      // On prépare le paquet de données (JSON)
      final payload = {
        "merchantId": merchantId,
        "amount": _amount,
        "description": _description,
        "channel": _channel,
        "countryCurrencyCode": _countryCurrencyCode,
        "referenceNumber": _referenceNumber,
        "customerEmail": _customerEmail,
        "customerFirstName": _customerFirstName,
        "customerLastname": _customerLastname,
        "customerPhoneNumber": _customerPhoneNumber,
        "notificationURL": _notificationURL,
        "returnURL": _returnURL,
        "returnContext": _returnContext,
      };

      // On envoie le paquet par internet (POST)
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 30));

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && data['url'] != null) {
        _paymentUrl = data['url'] as String;
        _success = data['success'] as bool? ?? false;
        return _success;
      } else {
        _message = data['message'] as String? ?? 'Erreur inconnue';
        return false;
      }
    } catch (e) {
      _message = 'Erreur de connexion : ${e.toString()}';
      return false;
    }
  }
}
