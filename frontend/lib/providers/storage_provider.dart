import 'package:flutter/foundation.dart';
import 'package:up2school/services/storage_service_interface.dart';

class StorageProvider extends ChangeNotifier {
  final StorageService _storageService;

  StorageProvider(this._storageService);

  StorageService get storage => _storageService;
}
