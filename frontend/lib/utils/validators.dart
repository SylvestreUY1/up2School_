class FormValidators {
  // Valider un champ requis
  static String? requiredValidator(String? value, {String? fieldName}) {
    if (value == null || value.isEmpty) {
      return fieldName != null 
          ? 'Le champ $fieldName est requis'
          : 'Ce champ est requis';
    }
    return null;
  }
  
  // Valider un email
  static String? emailValidator(String? value) {
    if (value == null || value.isEmpty) {
      return 'L\'email est requis';
    }
    
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
    );
    
    if (!emailRegex.hasMatch(value)) {
      return 'Email invalide';
    }
    
    return null;
  }
  
  // Valider un mot de passe
  static String? passwordValidator(String? value) {
    if (value == null || value.isEmpty) {
      return 'Le mot de passe est requis';
    }
    
    if (value.length < 6) {
      return 'Le mot de passe doit contenir au moins 6 caractères';
    }
    
    return null;
  }
  
  // Valider la confirmation de mot de passe
  static String? confirmPasswordValidator(String? value, String password) {
    if (value == null || value.isEmpty) {
      return 'Veuillez confirmer le mot de passe';
    }
    
    if (value != password) {
      return 'Les mots de passe ne correspondent pas';
    }
    
    return null;
  }
  
  // Valider un numéro de téléphone
  static String? phoneValidator(String? value) {
    if (value == null || value.isEmpty) {
      return null; // Optionnel
    }
    
    final phoneRegex = RegExp(r'^[0-9]{10}$');
    if (!phoneRegex.hasMatch(value.replaceAll(' ', ''))) {
      return 'Numéro de téléphone invalide';
    }
    
    return null;
  }
  
  // Valider un nom
  static String? nameValidator(String? value, {String fieldName = 'Nom'}) {
    if (value == null || value.isEmpty) {
      return 'Le $fieldName est requis';
    }
    
    if (value.length < 2) {
      return 'Le $fieldName doit contenir au moins 2 caractères';
    }
    
    return null;
  }
  
  // Valider une sélection
  static String? selectionValidator(String? value, {String fieldName = 'Ce champ'}) {
    if (value == null || value.isEmpty) {
      return 'Veuillez sélectionner $fieldName';
    }
    return null;
  }
}