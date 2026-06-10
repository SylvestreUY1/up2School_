String normalizeDocumentType(String? rawType) {
  final normalized = rawType?.trim().toLowerCase() ?? '';

  switch (normalized) {
    case 'cours':
      return 'cours';
    case 'td':
      return 'td';
    case 'sujets':
    case 'sujets d\'examen':
      return 'sujets';
    case 'projets':
      return 'projets';
    case 'autres':
    case 'autres ressources':
      return 'autres';
    default:
      return normalized;
  }
}
