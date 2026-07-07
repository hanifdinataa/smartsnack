// import 'package:dio/dio.dart';
// import 'package:flutter/foundation.dart';
// import 'package:image_picker/image_picker.dart';
// import 'dart:convert';

// import '../models/api_models.dart';
// import 'local_storage_service.dart';

// class ApiService {
//   static const _apiBaseFromDefine = String.fromEnvironment('API_BASE_URL', defaultValue: '');
//   static const _apiBaseListFromDefine = String.fromEnvironment('API_BASE_URLS', defaultValue: '');
//   static const _snackBoxDeviceId = String.fromEnvironment('SNACK_BOX_DEVICE_ID', defaultValue: 'esp32_health_01');

//   static String get _fallbackProductionBaseUrl => 'https://sugarcareid.arcloud.my.id';
//   static const _defaultLocalApiWeb = 'http://127.0.0.1:8000';

//   static String get _resolvedBaseUrl {
//     final defineBase = _sanitizeBaseUrl(_apiBaseFromDefine);
//     if (_isValidBaseUrl(defineBase)) {
//       return defineBase;
//     }

//     // Default untuk Flutter Web saat develop lokal.
//     if (kIsWeb) {
//       return _defaultLocalApiWeb;
//     }

//     // Default non-web saat debug lokal via USB (butuh `adb reverse tcp:8000 tcp:8000`).
//     if (kDebugMode) {
//       return 'http://127.0.0.1:8000';
//     }

//     // Fallback production.
//     return _fallbackProductionBaseUrl;
//   }

//   static List<String> get _candidateBaseUrls {
//     final candidates = <String>[];

//     void add(String value) {
//       final trimmed = _sanitizeBaseUrl(value);
//       if (trimmed.isEmpty) return;
//       if (!candidates.contains(trimmed)) {
//         candidates.add(trimmed);
//       }
//     }

//     add(_resolvedBaseUrl);

//     if (_apiBaseListFromDefine.isNotEmpty) {
//       for (final item in _apiBaseListFromDefine.split(',')) {
//         add(item);
//       }
//     }

//     if (kIsWeb) {
//       add('http://localhost:8000');
//       add('http://127.0.0.1:8000');
//       final browserHost = Uri.base.host;
//       if (browserHost.isNotEmpty && browserHost != 'localhost' && browserHost != '127.0.0.1') {
//         add('http://$browserHost:8000');
//       }
//       return candidates;
//     }

//     // Kandidat lokal umum untuk development mobile.
//     if (!kIsWeb) {
//       add('http://10.0.2.2:8000'); // Android emulator
//       add('http://127.0.0.1:8000'); // device + adb reverse
//     }

//     // Saat debug lokal, jangan otomatis lompat ke production karena bikin
//     // alur IoT lokal terlihat "error random" saat localhost tidak aktif.
//     if (!kDebugMode) {
//       add(_fallbackProductionBaseUrl);
//     }
//     return candidates;
//   }

//   static String _sanitizeBaseUrl(String raw) {
//     var value = raw.trim();
//     if (value.isEmpty) return '';

//     // Bersihkan typo umum dari argumen --dart-define.
//     value = value.replaceAll(' ', '');
//     value = value.replaceFirst('http:///','http://');
//     value = value.replaceFirst('https:///','https://');

//     // Hapus trailing slash agar path join konsisten.
//     while (value.endsWith('/')) {
//       value = value.substring(0, value.length - 1);
//     }

//     return value;
//   }

//   static bool _isValidBaseUrl(String value) {
//     if (value.isEmpty) return false;
//     final uri = Uri.tryParse(value);
//     if (uri == null) return false;
//     if (!(uri.scheme == 'http' || uri.scheme == 'https')) return false;
//     if (!uri.hasAuthority || uri.host.isEmpty) return false;
//     return true;
//   }

//   ApiService({required LocalStorageService storage})
//       : _storage = storage,
//         _dio = Dio(
//           BaseOptions(
//             baseUrl: _resolvedBaseUrl,
//             connectTimeout: const Duration(seconds: 10),
//             receiveTimeout: const Duration(seconds: 30),
//           ),
//         ) {
//     _dio.interceptors.add(
//       InterceptorsWrapper(
//         onRequest: (options, handler) {
//           final token = _storage.token;
//           final isAuthPath = options.path.contains('/api/login') || options.path.contains('/api/register');
//           if (!isAuthPath && token != null && token.isNotEmpty) {
//             options.headers['Authorization'] = 'Bearer $token';
//           }
//           handler.next(options);
//         },
//       ),
//     );
//   }

//   final Dio _dio;
//   final LocalStorageService _storage;
//   late final List<String> _baseCandidates = _candidateBaseUrls;
//   int _currentBaseIndex = 0;

//   Future<AuthData> login({required String email, required String password}) async {
//     final map = await _post('/api/login', data: {'email': email, 'password': password});
//     final envelope = ApiEnvelope<AuthData>.fromJson(map, (raw) => AuthData.fromJson(raw as Map<String, dynamic>));
//     final data = envelope.data;
//     if (data == null) throw Exception('Data login kosong');
//     return data;
//   }

//   Future<AuthData> register({
//     required String name,
//     required String email,
//     required String password,
//     required String passwordConfirmation,
//   }) async {
//     final map = await _post('/api/register', data: {
//       'name': name,
//       'email': email,
//       'password': password,
//       'password_confirmation': passwordConfirmation,
//     });

//     final envelope = ApiEnvelope<AuthData>.fromJson(map, (raw) => AuthData.fromJson(raw as Map<String, dynamic>));
//     final data = envelope.data;
//     if (data == null) throw Exception('Data register kosong');
//     return data;
//   }

//   Future<void> logout() async {
//     await _post('/api/logout');
//   }

//   Future<UserModel> getProfile() async {
//     final map = await _get('/api/user');
//     final envelope = ApiEnvelope<UserModel>.fromJson(map, (raw) => UserModel.fromJson(raw as Map<String, dynamic>));
//     final data = envelope.data;
//     if (data == null) throw Exception('Profil tidak ditemukan');
//     return data;
//   }

//   Future<UserModel> updateProfile({String? name, String? email}) async {
//     final data = <String, dynamic>{};
//     if (name != null && name.isNotEmpty) data['name'] = name;
//     if (email != null && email.isNotEmpty) data['email'] = email;

//     final map = await _patch('/api/user', data: data);
//     final envelope = ApiEnvelope<UserModel>.fromJson(map, (raw) => UserModel.fromJson(raw as Map<String, dynamic>));
//     final updated = envelope.data;
//     if (updated == null) throw Exception('Gagal update profil');
//     return updated;
//   }

//   Future<List<ProductItem>> getAllProducts() async {
//     final map = await _get('/api/products');
//     return _parseProductList(map);
//   }

//   Future<List<ProductItem>> searchProducts(String query) async {
//     final map = await _get('/api/products/search', queryParameters: {'q': query});
//     return _parseProductList(map);
//   }

//   Future<ProductItem?> findProductByLabel(String label) async {
//     final normalizedLabel = _normalizeProductLookupText(label);
//     if (normalizedLabel.isEmpty) {
//       return null;
//     }

//     final searchedProducts = await searchProducts(label);
//     final exactSearchMatch = _findExactProductMatch(searchedProducts, normalizedLabel);
//     if (exactSearchMatch != null) {
//       return exactSearchMatch;
//     }

//     final bestSearchMatch = _pickBestProductMatch(searchedProducts, normalizedLabel);
//     if (bestSearchMatch != null) {
//       return bestSearchMatch;
//     }

//     final allProducts = await getAllProducts();
//     final exactAllMatch = _findExactProductMatch(allProducts, normalizedLabel);
//     if (exactAllMatch != null) {
//       return exactAllMatch;
//     }

//     return _pickBestProductMatch(allProducts, normalizedLabel);
//   }


//   Future<NutritionScanResult> recognizeNutritionLabel({
//     required String name,
//     required String category,
//     required double grSugarContent,
//     required double netWeight,
//     String? scanSource,
//     String? image,
//     String? rawText,
//     XFile? productImageFile,
//   }) async {
//     if (productImageFile != null) {
//       if (kIsWeb) {
//         final bytes = await productImageFile.readAsBytes();
//         final base64Image = base64Encode(bytes);
//         final payload = <String, dynamic>{
//           'name': name.trim(),
//           'category': category,
//           'gr_sugar_content': grSugarContent,
//           'net_weight': netWeight,
//           'image': image,
//           'raw_text': rawText,
//           'scan_source': scanSource,
//           'product_image_base64': 'data:image/jpeg;base64,$base64Image',
//         };

//         final map = await _post('/api/products/recognize-nutrition-label', data: payload);
//         final envelope = ApiEnvelope<NutritionScanResult>.fromJson(
//           map,
//           (raw) => NutritionScanResult.fromJson(
//             (raw ?? <String, dynamic>{}) as Map<String, dynamic>,
//           ),
//         );
//         final data = envelope.data;
//         if (data == null) {
//           throw Exception('Produk dari label gizi tidak berhasil diproses.');
//         }
//         return data;
//       }

//       final filename = productImageFile.name.isNotEmpty ? productImageFile.name : 'product_image.jpg';
//       final MultipartFile imageMultipart;
//       imageMultipart = await MultipartFile.fromFile(productImageFile.path, filename: filename);

//       final payload = FormData.fromMap({
//         'name': name.trim(),
//         'category': category,
//         'gr_sugar_content': grSugarContent,
//         'net_weight': netWeight,
//         'image': image,
//         'raw_text': rawText,
//         'scan_source': scanSource,
//         'product_image': imageMultipart,
//       });

//       final map = await _postWithTimeout(
//         '/api/products/recognize-nutrition-label',
//         data: payload,
//         connectTimeout: const Duration(seconds: 20),
//         sendTimeout: const Duration(seconds: 120),
//         receiveTimeout: const Duration(seconds: 180),
//       );
//       final envelope = ApiEnvelope<NutritionScanResult>.fromJson(
//         map,
//         (raw) => NutritionScanResult.fromJson(
//           (raw ?? <String, dynamic>{}) as Map<String, dynamic>,
//         ),
//       );
//       final data = envelope.data;
//       if (data == null) {
//         throw Exception('Produk dari label gizi tidak berhasil diproses.');
//       }
//       return data;
//     }

//     final payload = <String, dynamic>{
//       'name': name.trim(),
//       'category': category,
//       'gr_sugar_content': grSugarContent,
//       'net_weight': netWeight,
//       'image': image,
//       'raw_text': rawText,
//     };
//     if (scanSource != null && scanSource.isNotEmpty) {
//       payload['scan_source'] = scanSource;
//     }

//     final map = await _post('/api/products/recognize-nutrition-label', data: payload);
//     final envelope = ApiEnvelope<NutritionScanResult>.fromJson(
//       map,
//       (raw) => NutritionScanResult.fromJson(
//         (raw ?? <String, dynamic>{}) as Map<String, dynamic>,
//       ),
//     );
//     final data = envelope.data;
//     if (data == null) {
//       throw Exception('Produk dari label gizi tidak berhasil diproses.');
//     }
//     return data;
//   }

//   Future<List<ArticleItem>> getArticles() async {
//     final map = await _get('/api/articles');
//     final envelope = ApiEnvelope<List<ArticleItem>>.fromJson(
//       map,
//       (raw) => (raw as List<dynamic>? ?? <dynamic>[])
//           .whereType<Map<String, dynamic>>()
//           .map(ArticleItem.fromJson)
//           .toList(),
//     );
//     return envelope.data ?? <ArticleItem>[];
//   }

//   Future<ArticleItem> getArticleDetail(int id) async {
//     final map = await _get('/api/articles/$id');
//     final envelope = ApiEnvelope<ArticleItem>.fromJson(
//       map,
//       (raw) => ArticleItem.fromJson((raw ?? <String, dynamic>{}) as Map<String, dynamic>),
//     );
//     final data = envelope.data;
//     if (data == null) throw Exception('Detail artikel tidak ditemukan');
//     return data;
//   }

//   Future<NutritionLabelDetectionResult> detectNutritionLabelFromFile(XFile imageFile) async {
//     final filename = imageFile.name.isNotEmpty ? imageFile.name : 'nutrition_image.jpg';
//     final MultipartFile imageMultipart;
//     if (kIsWeb) {
//       final bytes = await imageFile.readAsBytes();
//       imageMultipart = MultipartFile.fromBytes(bytes, filename: filename);
//     } else {
//       imageMultipart = await MultipartFile.fromFile(imageFile.path, filename: filename);
//     }

//     final form = FormData.fromMap({'image': imageMultipart});
//     final map = await _postWithTimeout(
//       '/api/products/detect-nutrition-image',
//       data: form,
//       connectTimeout: const Duration(seconds: 20),
//       sendTimeout: const Duration(seconds: 120),
//       receiveTimeout: const Duration(seconds: 180),
//     );
//     final envelope = ApiEnvelope<NutritionLabelDetectionResult>.fromJson(
//       map,
//       (raw) => NutritionLabelDetectionResult.fromJson(
//         (raw ?? <String, dynamic>{}) as Map<String, dynamic>,
//       ),
//     );
//     final data = envelope.data;
//     if (data == null) {
//       throw Exception('Gagal membaca gambar label gizi.');
//     }
//     return data;
//   }

//   Future<NutritionLabelDetectionResult> detectProductPackageFromFile(XFile imageFile) async {
//     final filename = imageFile.name.isNotEmpty ? imageFile.name : 'package_image.jpg';
//     final MultipartFile imageMultipart;
//     if (kIsWeb) {
//       final bytes = await imageFile.readAsBytes();
//       imageMultipart = MultipartFile.fromBytes(bytes, filename: filename);
//     } else {
//       imageMultipart = await MultipartFile.fromFile(imageFile.path, filename: filename);
//     }

//     final form = FormData.fromMap({'image': imageMultipart});
//     final map = await _postWithTimeout(
//       '/api/products/detect-package-image',
//       data: form,
//       connectTimeout: const Duration(seconds: 20),
//       sendTimeout: const Duration(seconds: 120),
//       receiveTimeout: const Duration(seconds: 180),
//     );
//     final envelope = ApiEnvelope<NutritionLabelDetectionResult>.fromJson(
//       map,
//       (raw) => NutritionLabelDetectionResult.fromJson(
//         (raw ?? <String, dynamic>{}) as Map<String, dynamic>,
//       ),
//     );
//     final data = envelope.data;
//     if (data == null) {
//       throw Exception('Gagal membaca foto kemasan produk.');
//     }
//     return data;
//   }

//   Future<NutritionLabelDetectionResult> detectCompleteFromFiles({
//     required XFile packageImageFile,
//     required XFile nutritionImageFile,
//   }) async {
//     final packageFilename = packageImageFile.name.isNotEmpty ? packageImageFile.name : 'package_image.jpg';
//     final nutritionFilename = nutritionImageFile.name.isNotEmpty ? nutritionImageFile.name : 'nutrition_image.jpg';

//     final MultipartFile packageMultipart;
//     final MultipartFile nutritionMultipart;
//     if (kIsWeb) {
//       final packageBytes = await packageImageFile.readAsBytes();
//       final nutritionBytes = await nutritionImageFile.readAsBytes();
//       packageMultipart = MultipartFile.fromBytes(packageBytes, filename: packageFilename);
//       nutritionMultipart = MultipartFile.fromBytes(nutritionBytes, filename: nutritionFilename);
//     } else {
//       packageMultipart = await MultipartFile.fromFile(packageImageFile.path, filename: packageFilename);
//       nutritionMultipart = await MultipartFile.fromFile(nutritionImageFile.path, filename: nutritionFilename);
//     }

//     final form = FormData.fromMap({
//       'package_image': packageMultipart,
//       'nutrition_image': nutritionMultipart,
//     });

//     final map = await _postWithTimeout(
//       '/api/products/detect-complete-image',
//       data: form,
//       connectTimeout: const Duration(seconds: 20),
//       sendTimeout: const Duration(seconds: 180),
//       receiveTimeout: const Duration(seconds: 240),
//     );

//     final envelope = ApiEnvelope<NutritionLabelDetectionResult>.fromJson(
//       map,
//       (raw) => NutritionLabelDetectionResult.fromJson(
//         (raw ?? <String, dynamic>{}) as Map<String, dynamic>,
//       ),
//     );
//     final data = envelope.data;
//     if (data == null) {
//       throw Exception('Gagal membaca foto kemasan + label gizi.');
//     }
//     return data;
//   }


//   Future<NutritionLabelDetectionResult> detectNutritionLabelFromBytes(
//     Uint8List bytes, {
//     String filename = 'captured_nutrition.jpg',
//   }) async {
//     final form = FormData.fromMap({
//       'image': MultipartFile.fromBytes(bytes, filename: filename),
//     });
//     final map = await _postWithTimeout(
//       '/api/products/detect-nutrition-image',
//       data: form,
//       connectTimeout: const Duration(seconds: 20),
//       sendTimeout: const Duration(seconds: 120),
//       receiveTimeout: const Duration(seconds: 180),
//     );
//     final envelope = ApiEnvelope<NutritionLabelDetectionResult>.fromJson(
//       map,
//       (raw) => NutritionLabelDetectionResult.fromJson(
//         (raw ?? <String, dynamic>{}) as Map<String, dynamic>,
//       ),
//     );
//     final data = envelope.data;
//     if (data == null) {
//       throw Exception('Gagal membaca gambar label gizi.');
//     }
//     return data;
//   }


//   Future<ProductDetail> getProductDetail(int id) async {
//     final map = await _get('/api/products/$id');
//     final envelope = ApiEnvelope<ProductDetail>.fromJson(map, (raw) => ProductDetail.fromJson(raw as Map<String, dynamic>));
//     final data = envelope.data;
//     if (data == null) throw Exception('Detail produk tidak ditemukan');
//     return data;
//   }

//   Future<List<ProductItem>> getRecommendations(int productId) async {
//     final map = await _get('/api/recommendation/$productId');
//     final envelope = ApiEnvelope<List<ProductItem>>.fromJson(
//       map,
//       (raw) => (raw as List<dynamic>? ?? <dynamic>[])
//           .whereType<Map<String, dynamic>>()
//           .map(ProductItem.fromJson)
//           .toList(),
//     );
//     return envelope.data ?? <ProductItem>[];
//   }

//   Future<void> saveSearchProduct(int productId) async {
//     await _post('/api/user-search-history-product', data: {'product_id': productId});
//   }

//   Future<void> consumeProduct({required int productId, int percentageConsumed = 1}) async {
//     await _post('/api/user-consumption', data: {
//       'product_id': productId,
//       'percentage_consumed': percentageConsumed,
//     });
//   }

//   Future<SnackBoxStatus> activateSnackBox({String? deviceId}) async {
//     final payload = <String, dynamic>{};
//     final resolvedDeviceId = (deviceId ?? _snackBoxDeviceId).trim();
//     if (resolvedDeviceId.isNotEmpty) {
//       payload['device_id'] = resolvedDeviceId;
//     }

//     final map = await _post('/api/snack-box/activate', data: payload);
//     final envelope = ApiEnvelope<SnackBoxStatus>.fromJson(
//       map,
//       (raw) => SnackBoxStatus.fromJson((raw ?? <String, dynamic>{}) as Map<String, dynamic>),
//     );
//     final data = envelope.data;
//     if (data == null) {
//       throw Exception('Status Smart Snack Box tidak ditemukan.');
//     }
//     return data;
//   }

//   Future<SnackBoxStatus> getSnackBoxStatus({String? deviceId}) async {
//     final queryParameters = <String, dynamic>{};
//     final resolvedDeviceId = (deviceId ?? _snackBoxDeviceId).trim();
//     if (resolvedDeviceId.isNotEmpty) {
//       queryParameters['device_id'] = resolvedDeviceId;
//     }

//     final map = await _get('/api/snack-box/status', queryParameters: queryParameters);
//     final envelope = ApiEnvelope<SnackBoxStatus>.fromJson(
//       map,
//       (raw) => SnackBoxStatus.fromJson((raw ?? <String, dynamic>{}) as Map<String, dynamic>),
//     );
//     final data = envelope.data;
//     if (data == null) {
//       throw Exception('Status Smart Snack Box tidak tersedia.');
//     }
//     return data;
//   }

//   Future<void> deleteConsumedProduct({required int consumptionRecordId}) async {
//     try {
//       await _requestWithFailover(
//         () => _dio.delete<Map<String, dynamic>>('/api/user-consumption/$consumptionRecordId'),
//       );
//     } on DioException catch (e) {
//       throw Exception(_resolveErrorMessage(e));
//     }
//   }

//   Future<int> deleteAllConsumedProducts() async {
//     final map = await _delete('/api/user-consumption');
//     final envelope = ApiEnvelope<int>.fromJson(
//       map,
//       (raw) {
//         if (raw is Map<String, dynamic>) {
//           return int.tryParse((raw['deleted_count'] ?? 0).toString()) ?? 0;
//         }
//         return 0;
//       },
//     );
//     return envelope.data ?? 0;
//   }

//   Future<List<ProductItem>> getSearchHistory() async {
//     final map = await _get('/api/user-search-history-product');
//     final envelope = ApiEnvelope<List<ProductItem>>.fromJson(
//       map,
//       (raw) => (raw as List<dynamic>? ?? <dynamic>[])
//           .whereType<Map<String, dynamic>>()
//           .map(ProductItem.fromJson)
//           .toList(),
//     );
//     return envelope.data ?? <ProductItem>[];
//   }

//   Future<List<ProductItem>> getConsumedProducts() async {
//     final map = await _get('/api/user-consumption');
//     final envelope = ApiEnvelope<List<ProductItem>>.fromJson(
//       map,
//       (raw) => (raw as List<dynamic>? ?? <dynamic>[])
//           .whereType<Map<String, dynamic>>()
//           .map(ProductItem.fromJson)
//           .toList(),
//     );
//     return envelope.data ?? <ProductItem>[];
//   }

//   Future<double> getTodaySugar() async {
//     final map = await _get('/api/report/user/sugar/today');
//     final envelope = ApiEnvelope<double>.fromJson(map, (raw) {
//       if (raw == null) return 0;
//       return double.tryParse(raw.toString()) ?? 0;
//     });
//     return envelope.data ?? 0;
//   }

//   Future<Map<String, dynamic>> checkHeartRate() async {
//     return _postWithTimeout(
//       '/api/health-monitoring/check-heart-rate',
//       connectTimeout: const Duration(seconds: 120),
//       sendTimeout: const Duration(seconds: 30),
//       receiveTimeout: const Duration(seconds: 180),
//     );
//   }

//   Future<Map<String, dynamic>> checkBodyTemperature({required int checkId}) async {
//     return _postWithTimeout(
//       '/api/health-monitoring/check-body-temperature',
//       data: {'check_id': checkId},
//       connectTimeout: const Duration(seconds: 60),
//       sendTimeout: const Duration(seconds: 20),
//       receiveTimeout: const Duration(seconds: 60),
//     );
//   }

//   Future<HealthMonitoringRecord> analyzeHealthMonitoring({
//     required int checkId,
//     required int age,
//     required String gender,
//     required double heightCm,
//     required double weightKg,
//     required double bmi,
//   }) async {
//     final map = await _post('/api/health-monitoring/analyze', data: {
//       'check_id': checkId,
//       'age': age,
//       'gender': gender,
//       'height_cm': heightCm,
//       'weight_kg': weightKg,
//       'bmi': bmi,
//     });
//     final envelope = ApiEnvelope<HealthMonitoringRecord>.fromJson(
//       map,
//       (raw) => HealthMonitoringRecord.fromJson((raw ?? <String, dynamic>{}) as Map<String, dynamic>),
//     );
//     final data = envelope.data;
//     if (data == null) {
//       throw Exception('Gagal memproses monitoring kesehatan.');
//     }
//     return data;
//   }

//   Future<List<HealthMonitoringRecord>> getHealthMonitoringHistory() async {
//     final map = await _get('/api/health-monitoring/history');
//     final envelope = ApiEnvelope<List<HealthMonitoringRecord>>.fromJson(
//       map,
//       (raw) => (raw as List<dynamic>? ?? <dynamic>[])
//           .whereType<Map<String, dynamic>>()
//           .map(HealthMonitoringRecord.fromJson)
//           .toList(),
//     );
//     return envelope.data ?? <HealthMonitoringRecord>[];
//   }

//   Future<List<ReportListItem>> getWeeklyReports() async {
//     final map = await _get('/api/report/user/sugar/weekly-list');
//     return _parseReportList(map);
//   }

//   Future<List<ReportListItem>> getMonthlyReports() async {
//     final map = await _get('/api/report/user/sugar/monthly-list');
//     return _parseReportList(map);
//   }

//   Future<List<ReportListItem>> getYearlyReports() async {
//     final map = await _get('/api/report/user/sugar/yearly-list');
//     return _parseReportList(map);
//   }

//   Future<List<ReportListItem>> searchReports(String query) async {
//     final map = await _get('/api/report/user/sugar/search', queryParameters: {'query': query});
//     return _parseReportList(map);
//   }

//   Future<List<WeeklyChartPoint>> getWeeklyChart(int reportId) async {
//     final map = await _get('/api/report/user/consumption/$reportId');
//     final envelope = ApiEnvelope<List<WeeklyChartPoint>>.fromJson(
//       map,
//       (raw) => (raw as List<dynamic>? ?? <dynamic>[])
//           .whereType<Map<String, dynamic>>()
//           .map(WeeklyChartPoint.fromJson)
//           .toList(),
//     );
//     return envelope.data ?? <WeeklyChartPoint>[];
//   }

//   Future<List<MonthlyChartPoint>> getMonthlyChart({required String month, required int year}) async {
//     final map = await _get(
//       '/api/report/user/monthly-consumption',
//       queryParameters: {'month': month, 'year': year},
//     );
//     final envelope = ApiEnvelope<List<MonthlyChartPoint>>.fromJson(
//       map,
//       (raw) => (raw as List<dynamic>? ?? <dynamic>[])
//           .whereType<Map<String, dynamic>>()
//           .map(MonthlyChartPoint.fromJson)
//           .toList(),
//     );
//     return envelope.data ?? <MonthlyChartPoint>[];
//   }

//   Future<List<YearlyChartPoint>> getYearlyChart({required int year}) async {
//     final map = await _get('/api/report/user/yearly-consumption', queryParameters: {'year': year});
//     final envelope = ApiEnvelope<List<YearlyChartPoint>>.fromJson(
//       map,
//       (raw) => (raw as List<dynamic>? ?? <dynamic>[])
//           .whereType<Map<String, dynamic>>()
//           .map(YearlyChartPoint.fromJson)
//           .toList(),
//     );
//     return envelope.data ?? <YearlyChartPoint>[];
//   }

//   Future<void> suggestProduct({
//     required String name,
//     required String category,
//     required double grSugarContent,
//     required double netWeight,
//     required double servingsPerPackage,
//     required double servingSizeMl,
//     required XFile imageFile,
//   }) async {
//     final filename = imageFile.name.isNotEmpty ? imageFile.name : 'product_image.jpg';
//     final MultipartFile imageMultipart;
//     if (kIsWeb) {
//       final bytes = await imageFile.readAsBytes();
//       imageMultipart = MultipartFile.fromBytes(bytes, filename: filename);
//     } else {
//       imageMultipart = await MultipartFile.fromFile(imageFile.path, filename: filename);
//     }

//     final form = FormData.fromMap({
//       'name': name,
//       'category': category,
//       'gr_sugar_content': grSugarContent,
//       'net_weight': netWeight,
//       'servings_per_package': servingsPerPackage,
//       'serving_size_ml': servingSizeMl,
//       'image': imageMultipart,
//     });

//     await _post('/api/suggested-products', data: form);
//   }

//   Future<int?> classifyProductByImage(XFile imageFile) async {
//     final filename = imageFile.name.isNotEmpty ? imageFile.name : 'captured_image.jpg';
//     final MultipartFile imageMultipart;
//     if (kIsWeb) {
//       final bytes = await imageFile.readAsBytes();
//       imageMultipart = MultipartFile.fromBytes(bytes, filename: filename);
//     } else {
//       imageMultipart = await MultipartFile.fromFile(imageFile.path, filename: filename);
//     }

//     final form = FormData.fromMap({'image': imageMultipart});

//     try {
//       final response = await _requestWithFailover(
//         () => _dio.post<Map<String, dynamic>>(
//           '/api/classify-product',
//           data: form,
//           options: Options(
//             connectTimeout: const Duration(seconds: 20),
//             sendTimeout: const Duration(seconds: 120),
//             receiveTimeout: const Duration(seconds: 180),
//           ),
//         ),
//       );
//       final map = _extractMap(response.data);
//       final data = map['data'];
//       if (data is! Map<String, dynamic>) {
//         return null;
//       }

//       final rawId = data['predicted_product_id'] ?? data['product_id'];
//       if (rawId == null) return null;
//       if (rawId is int) return rawId;
//       return int.tryParse(rawId.toString());
//     } on DioException catch (e) {
//       if (e.response?.statusCode == 422) {
//         return null;
//       }
//       throw Exception(_resolveErrorMessage(e));
//     }
//   }

//   Future<Map<String, dynamic>> _get(String path, {Map<String, dynamic>? queryParameters}) async {
//     try {
//       final response = await _requestWithFailover(
//         () => _dio.get<Map<String, dynamic>>(path, queryParameters: queryParameters),
//       );
//       return _extractMap(response.data);
//     } on DioException catch (e) {
//       throw Exception(_resolveErrorMessage(e));
//     }
//   }

//   Future<Map<String, dynamic>> _post(String path, {dynamic data}) async {
//     try {
//       final response = await _requestWithFailover(
//         () => _dio.post<Map<String, dynamic>>(path, data: data),
//       );
//       return _extractMap(response.data);
//     } on DioException catch (e) {
//       throw Exception(_resolveErrorMessage(e));
//     }
//   }

//   Future<Map<String, dynamic>> _postWithTimeout(
//     String path, {
//     dynamic data,
//     required Duration connectTimeout,
//     required Duration sendTimeout,
//     required Duration receiveTimeout,
//   }) async {
//     try {
//       final response = await _requestWithFailover(
//         () => _dio.post<Map<String, dynamic>>(
//           path,
//           data: data,
//           options: Options(
//             connectTimeout: connectTimeout,
//             sendTimeout: sendTimeout,
//             receiveTimeout: receiveTimeout,
//           ),
//         ),
//       );
//       return _extractMap(response.data);
//     } on DioException catch (e) {
//       throw Exception(_resolveErrorMessage(e));
//     }
//   }

//   Future<Map<String, dynamic>> _patch(String path, {dynamic data}) async {
//     try {
//       final response = await _requestWithFailover(
//         () => _dio.patch<Map<String, dynamic>>(path, data: data),
//       );
//       return _extractMap(response.data);
//     } on DioException catch (e) {
//       throw Exception(_resolveErrorMessage(e));
//     }
//   }

//   Future<Map<String, dynamic>> _delete(String path) async {
//     try {
//       final response = await _requestWithFailover(
//         () => _dio.delete<Map<String, dynamic>>(path),
//       );
//       return _extractMap(response.data);
//     } on DioException catch (e) {
//       throw Exception(_resolveErrorMessage(e));
//     }
//   }

//   Future<Response<Map<String, dynamic>>> _requestWithFailover(
//     Future<Response<Map<String, dynamic>>> Function() request,
//   ) async {
//     DioException? lastError;

//     for (var i = 0; i < _baseCandidates.length; i++) {
//       final idx = (_currentBaseIndex + i) % _baseCandidates.length;
//       final base = _baseCandidates[idx];
//       _dio.options.baseUrl = base;

//       try {
//         final response = await request();
//         _currentBaseIndex = idx;
//         return response;
//       } on DioException catch (e) {
//         lastError = e;
//         if (!_isConnectionIssue(e)) {
//           rethrow;
//         }
//       }
//     }

//     throw lastError ??
//         DioException(
//           requestOptions: RequestOptions(path: ''),
//           type: DioExceptionType.unknown,
//           error: 'Unknown network error',
//         );
//   }

//   Map<String, dynamic> _extractMap(Map<String, dynamic>? data) {
//     if (data == null) {
//       throw Exception('Respon API kosong');
//     }

//     final success = data['success'] == true;
//     if (!success) {
//       final message = (data['message'] ?? 'Permintaan gagal').toString();
//       throw Exception(message);
//     }

//     _normalizePayloadImageUrls(data);
//     return data;
//   }

//   void _normalizePayloadImageUrls(dynamic node) {
//     if (node is Map<String, dynamic>) {
//       for (final entry in node.entries) {
//         final key = entry.key.toLowerCase();
//         final value = entry.value;
//         if ((key == 'image' || key == 'product_image') && value is String) {
//           node[entry.key] = _resolveMediaUrl(value);
//           continue;
//         }
//         _normalizePayloadImageUrls(value);
//       }
//       return;
//     }

//     if (node is List) {
//       for (final item in node) {
//         _normalizePayloadImageUrls(item);
//       }
//     }
//   }

//   String _resolveMediaUrl(String rawValue) {
//     final raw = rawValue.trim();
//     if (raw.isEmpty) return raw;

//     final base = Uri.tryParse(_dio.options.baseUrl);
//     if (base == null) return raw;

//     if (raw.startsWith('/')) {
//       return base.resolve(raw).toString();
//     }

//     if (raw.startsWith('storage/')) {
//       return base.resolve('/$raw').toString();
//     }

//     final uri = Uri.tryParse(raw);
//     if (uri == null || !uri.hasScheme) return raw;

//     final isLocalLoopback = uri.host == '127.0.0.1' || uri.host == 'localhost';
//     if (!isLocalLoopback) return raw;

//     if (base.host == '127.0.0.1' || base.host == 'localhost') {
//       return raw;
//     }

//     return uri.replace(
//       scheme: base.scheme,
//       host: base.host,
//       port: base.hasPort ? base.port : null,
//     ).toString();
//   }

//   String _resolveErrorMessage(DioException exception) {
//     final statusCode = exception.response?.statusCode;

//     if (kDebugMode) {
//       debugPrint(
//         '[ApiService] Request failed baseUrl=${_dio.options.baseUrl} '
//         'path=${exception.requestOptions.path} status=$statusCode type=${exception.type}',
//       );
//     }

//     if (_isConnectionIssue(exception)) {
//       if (exception.type == DioExceptionType.receiveTimeout) {
//         return 'Waktu tunggu sensor habis. Pastikan ESP32 merespons endpoint detak/suhu dan ulangi pengecekan.';
//       }

//       if (kIsWeb) {
//         return 'Tidak dapat terhubung ke API lokal (${_dio.options.baseUrl}). '
//             'Pastikan backend aktif (Docker: `docker-compose up -d --build backend label-gizi-service`) '
//             'atau Laravel lokal: `php artisan serve --host=127.0.0.1 --port=8000`.';
//       }

//       return 'Tidak dapat terhubung ke API (${_dio.options.baseUrl}). '
//           'Jika pakai HP fisik + backend lokal, jalankan `adb reverse tcp:8000 tcp:8000` '
//           'atau jalankan app dengan `--dart-define=API_BASE_URL=http://IP_LAPTOP:8000`.';
//     }

//     final responseData = exception.response?.data;
//     if (responseData is Map<String, dynamic>) {
//       final message = responseData['message'];
//       if (message != null && message.toString().isNotEmpty) {
//         final errors = responseData['errors'];
//         if (errors is Map<String, dynamic>) {
//           final imageErrors = errors['image'];
//           if (imageErrors is List && imageErrors.isNotEmpty) {
//             return imageErrors.first.toString();
//           }
//           final productImageErrors = errors['product_image'];
//           if (productImageErrors is List && productImageErrors.isNotEmpty) {
//             return productImageErrors.first.toString();
//           }
//           for (final value in errors.values) {
//             if (value is List && value.isNotEmpty) {
//               return value.first.toString();
//             }
//           }
//         }
//         return message.toString();
//       }
//     }
//     if (responseData is String && responseData.trim().startsWith('{')) {
//       try {
//         final decoded = jsonDecode(responseData);
//         if (decoded is Map<String, dynamic>) {
//           final message = decoded['message'];
//           if (message != null && message.toString().isNotEmpty) {
//             return message.toString();
//           }
//         }
//       } catch (_) {
//         // Ignore JSON parse failure.
//       }
//     }

//     if (statusCode != null) {
//       if (statusCode == 401) {
//         return 'Sesi login berakhir. Silakan login ulang.';
//       }
//       if (statusCode == 403) {
//         return 'Anda tidak memiliki akses untuk aksi ini.';
//       }
//       if (statusCode == 422) {
//         return 'Data yang dikirim tidak valid. Cek lagi input Anda.';
//       }
//       if (statusCode >= 500) {
//         return 'Server backend sedang bermasalah ($statusCode). Coba lagi sebentar.';
//       }
//     }

//     if (exception.message != null && exception.message!.isNotEmpty) {
//       return exception.message!;
//     }

//     return 'Terjadi kesalahan jaringan.';
//   }

//   bool _isConnectionIssue(DioException exception) {
//     return exception.type == DioExceptionType.connectionError ||
//         exception.type == DioExceptionType.connectionTimeout ||
//         exception.type == DioExceptionType.receiveTimeout ||
//         exception.type == DioExceptionType.sendTimeout;
//   }

//   List<ProductItem> _parseProductList(Map<String, dynamic> map) {
//     final envelope = ApiEnvelope<List<ProductItem>>.fromJson(
//       map,
//       (raw) => (raw as List<dynamic>? ?? <dynamic>[])
//           .whereType<Map<String, dynamic>>()
//           .map(ProductItem.fromJson)
//           .toList(),
//     );
//     return envelope.data ?? <ProductItem>[];
//   }

//   List<ReportListItem> _parseReportList(Map<String, dynamic> map) {
//     final envelope = ApiEnvelope<List<ReportListItem>>.fromJson(
//       map,
//       (raw) => (raw as List<dynamic>? ?? <dynamic>[])
//           .whereType<Map<String, dynamic>>()
//           .map(ReportListItem.fromJson)
//           .toList(),
//     );
//     return envelope.data ?? <ReportListItem>[];
//   }

//   ProductItem? _findExactProductMatch(List<ProductItem> products, String normalizedLabel) {
//     for (final product in products) {
//       if (_normalizeProductLookupText(product.name) == normalizedLabel) {
//         return product;
//       }
//     }
//     return null;
//   }

//   ProductItem? _pickBestProductMatch(List<ProductItem> products, String normalizedLabel) {
//     final labelTokens = _lookupTokens(normalizedLabel);
//     if (products.isEmpty || labelTokens.isEmpty) {
//       return null;
//     }

//     ProductItem? best;
//     var bestScore = double.negativeInfinity;

//     for (final product in products) {
//       final normalizedProduct = _normalizeProductLookupText(product.name);
//       if (normalizedProduct.isEmpty) {
//         continue;
//       }

//       final productTokens = _lookupTokens(normalizedProduct);
//       var score = 0.0;

//       if (normalizedProduct == normalizedLabel) {
//         score += 120;
//       }
//       if (normalizedProduct.contains(normalizedLabel) && normalizedLabel.length >= 4) {
//         score += 45;
//       }
//       if (normalizedLabel.contains(normalizedProduct) && normalizedProduct.length >= 4) {
//         score += 40;
//       }

//       final nameSimilarity = _stringSimilarity(normalizedLabel, normalizedProduct);
//       score += nameSimilarity * 40;

//       final overlap = labelTokens.intersection(productTokens).length;
//       score += overlap * 14;

//       final unmatchedLabel = labelTokens.length - overlap;
//       final unmatchedProduct = productTokens.length - overlap;
//       score -= unmatchedLabel * 2;
//       score -= unmatchedProduct * 2;

//       final firstLabelToken = labelTokens.isNotEmpty ? labelTokens.first : '';
//       final firstProductToken = productTokens.isNotEmpty ? productTokens.first : '';
//       if (firstLabelToken.isNotEmpty &&
//           firstProductToken.isNotEmpty &&
//           _stringSimilarity(firstLabelToken, firstProductToken) >= 0.75) {
//         score += 18;
//       }

//       if (score > bestScore) {
//         bestScore = score;
//         best = product;
//       }
//     }

//     if (bestScore < 10) {
//       return null;
//     }
//     return best;
//   }

//   String _normalizeProductLookupText(String value) {
//     return value
//         .toLowerCase()
//         .replaceAll('&', ' and ')
//         .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
//         .replaceAll(RegExp(r'\s+'), ' ')
//         .trim();
//   }

//   Set<String> _lookupTokens(String value) {
//     return value.split(' ').where((token) => token.length >= 3).toSet();
//   }

//   double _stringSimilarity(String left, String right) {
//     if (left.isEmpty || right.isEmpty) return 0;
//     if (left == right) return 1;

//     final distance = _levenshteinDistance(left, right);
//     final maxLength = left.length > right.length ? left.length : right.length;
//     if (maxLength == 0) return 0;

//     return 1 - (distance / maxLength);
//   }

//   int _levenshteinDistance(String left, String right) {
//     if (left == right) return 0;
//     if (left.isEmpty) return right.length;
//     if (right.isEmpty) return left.length;

//     var previous = List<int>.generate(right.length + 1, (index) => index);
//     var current = List<int>.filled(right.length + 1, 0);

//     for (var i = 1; i <= left.length; i++) {
//       current[0] = i;
//       for (var j = 1; j <= right.length; j++) {
//         final substitutionCost = left.codeUnitAt(i - 1) == right.codeUnitAt(j - 1) ? 0 : 1;
//         final deletion = previous[j] + 1;
//         final insertion = current[j - 1] + 1;
//         final substitution = previous[j - 1] + substitutionCost;
//         current[j] = deletion < insertion
//             ? (deletion < substitution ? deletion : substitution)
//             : (insertion < substitution ? insertion : substitution);
//       }
//       final temp = previous;
//       previous = current;
//       current = temp;
//     }

//     return previous[right.length];
//   }
// }

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';

import '../models/api_models.dart';
import 'local_storage_service.dart';

class ApiService {
  static const _apiBaseFromDefine = String.fromEnvironment('API_BASE_URL', defaultValue: '');
  static const _apiBaseListFromDefine = String.fromEnvironment('API_BASE_URLS', defaultValue: '');
  static const _snackBoxDeviceId = String.fromEnvironment('SNACK_BOX_DEVICE_ID', defaultValue: 'esp32_health_01');

  static String get _fallbackProductionBaseUrl => 'http://54.144.6.206:8000';
  static const _defaultLocalApiWeb = 'http://54.144.6.206:8000';

  static String get _resolvedBaseUrl {
    final defineBase = _sanitizeBaseUrl(_apiBaseFromDefine);
    if (_isValidBaseUrl(defineBase)) {
      return defineBase;
    }

    // Untuk web release, langsung gunakan endpoint production.
    if (kIsWeb) {
      if (!kDebugMode) {
        return _fallbackProductionBaseUrl;
      }
      return _defaultLocalApiWeb;
    }

    // Default non-web saat debug lokal via USB (butuh `adb reverse tcp:8000 tcp:8000`).
    if (kDebugMode) {
      return 'http://54.144.6.206:8000';
    }

    // Fallback production.
    return _fallbackProductionBaseUrl;
  }

  static List<String> get _candidateBaseUrls {
    final candidates = <String>[];

    void add(String value) {
      final trimmed = _sanitizeBaseUrl(value);
      if (trimmed.isEmpty) return;
      if (!candidates.contains(trimmed)) {
        candidates.add(trimmed);
      }
    }

    add(_resolvedBaseUrl);

    if (_apiBaseListFromDefine.isNotEmpty) {
      for (final item in _apiBaseListFromDefine.split(',')) {
        add(item);
      }
    }

    if (kIsWeb) {
      add('http://54.144.6.206:8000');
      add('http://127.0.0.1:8000');
      final browserHost = Uri.base.host;
      if (browserHost.isNotEmpty && browserHost != 'localhost' && browserHost != '127.0.0.1') {
        add('http://$browserHost:8000');
      }
      // `localhost` kadang resolve ke jalur loopback yang berbeda (IPv6/bridge)
      // dan memicu timeout acak pada beberapa setup Docker/Windows.
      add('http://localhost:8000');
      return candidates;
    }

    // Kandidat lokal untuk HP fisik + backend lokal (Docker) via adb reverse.
    if (!kIsWeb) {
      add('http://54.144.6.206:8000');
      add('http://127.0.0.1:8000'); // device + adb reverse
    }

    // Saat debug lokal, jangan otomatis lompat ke production karena bikin
    // alur IoT lokal terlihat "error random" saat localhost tidak aktif.
    if (!kDebugMode) {
      add(_fallbackProductionBaseUrl);
    }
    return candidates;
  }

  static String _sanitizeBaseUrl(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return '';

    // Bersihkan typo umum dari argumen --dart-define.
    value = value.replaceAll(' ', '');
    value = value.replaceFirst('http:///','http://');
    value = value.replaceFirst('https:///','https://');

    // Hapus trailing slash agar path join konsisten.
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }

    return value;
  }

  static bool _isValidBaseUrl(String value) {
    if (value.isEmpty) return false;
    final uri = Uri.tryParse(value);
    if (uri == null) return false;
    if (!(uri.scheme == 'http' || uri.scheme == 'https')) return false;
    if (!uri.hasAuthority || uri.host.isEmpty) return false;
    return true;
  }

  ApiService({required LocalStorageService storage})
      : _storage = storage,
        _dio = Dio(
          BaseOptions(
            baseUrl: _resolvedBaseUrl,
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 30),
          ),
        ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = _storage.token;
          final isAuthPath = options.path.contains('/api/login') || options.path.contains('/api/register');
          if (!isAuthPath && token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
      ),
    );
  }

  final Dio _dio;
  final LocalStorageService _storage;
  late final List<String> _baseCandidates = _candidateBaseUrls;
  int _currentBaseIndex = 0;

  Future<AuthData> login({required String email, required String password}) async {
    final map = await _post('/api/login', data: {'email': email, 'password': password});
    final envelope = ApiEnvelope<AuthData>.fromJson(map, (raw) => AuthData.fromJson(raw as Map<String, dynamic>));
    final data = envelope.data;
    if (data == null) throw Exception('Data login kosong');
    return data;
  }

  Future<AuthData> register({
    required String name,
    required String email,
    required String password,
    required String passwordConfirmation,
  }) async {
    final map = await _post('/api/register', data: {
      'name': name,
      'email': email,
      'password': password,
      'password_confirmation': passwordConfirmation,
    });

    final envelope = ApiEnvelope<AuthData>.fromJson(map, (raw) => AuthData.fromJson(raw as Map<String, dynamic>));
    final data = envelope.data;
    if (data == null) throw Exception('Data register kosong');
    return data;
  }

  Future<void> logout() async {
    await _post('/api/logout');
  }

  Future<UserModel> getProfile() async {
    final map = await _get('/api/user');
    final envelope = ApiEnvelope<UserModel>.fromJson(map, (raw) => UserModel.fromJson(raw as Map<String, dynamic>));
    final data = envelope.data;
    if (data == null) throw Exception('Profil tidak ditemukan');
    return data;
  }

  Future<UserModel> updateProfile({String? name, String? email}) async {
    final data = <String, dynamic>{};
    if (name != null && name.isNotEmpty) data['name'] = name;
    if (email != null && email.isNotEmpty) data['email'] = email;

    final map = await _patch('/api/user', data: data);
    final envelope = ApiEnvelope<UserModel>.fromJson(map, (raw) => UserModel.fromJson(raw as Map<String, dynamic>));
    final updated = envelope.data;
    if (updated == null) throw Exception('Gagal update profil');
    return updated;
  }

  Future<List<ProductItem>> getAllProducts() async {
    final map = await _get('/api/products');
    return _parseProductList(map);
  }

  Future<List<ProductItem>> searchProducts(String query) async {
    final map = await _get('/api/products/search', queryParameters: {'q': query});
    return _parseProductList(map);
  }

  Future<ProductItem?> findProductByLabel(
    String label, {
    String? category,
    bool allowFuzzyFallback = true,
  }) async {
    final normalizedLabel = _normalizeProductLookupText(label);
    if (normalizedLabel.isEmpty) {
      return null;
    }

    try {
      final query = <String, dynamic>{'label': label};
      if (category != null && category.isNotEmpty) {
        query['category'] = category;
      }
      final map = await _get('/api/products/find-by-label', queryParameters: query);
      final envelope = ApiEnvelope<ProductItem>.fromJson(
        map,
        (raw) => ProductItem.fromJson((raw ?? <String, dynamic>{}) as Map<String, dynamic>),
      );
      if (envelope.data != null) {
        return envelope.data;
      }
    } catch (_) {
      // Lanjut ke pencarian lokal API supaya scan tetap punya fallback.
    }

    if (!allowFuzzyFallback) {
      return null;
    }

    // FIX: Wrap searchProducts dalam try-catch.
    // Jika backend return {success: false} (misal tidak ada hasil),
    // _extractMap() akan throw Exception — tanpa try-catch ini,
    // seluruh findProductByLabel ikut crash dan return null via catch di atas.
    List<ProductItem> searchedProducts = [];
    try {
      searchedProducts = await searchProducts(label);
    } catch (_) {
      // Backend error / tidak ada hasil — lanjut ke fallback getAllProducts()
    }

    if (category != null && category.isNotEmpty) {
      searchedProducts = searchedProducts.where((item) => item.category == category).toList();
    }

    if (searchedProducts.isNotEmpty) {
      final exactSearchMatch = _findExactProductMatch(searchedProducts, normalizedLabel);
      if (exactSearchMatch != null) {
        return exactSearchMatch;
      }

      final bestSearchMatch = _pickBestProductMatch(searchedProducts, normalizedLabel);
      if (bestSearchMatch != null) {
        return bestSearchMatch;
      }
    }

    // Fallback: ambil semua produk dan cari yang paling cocok (fuzzy match)
    List<ProductItem> allProducts = [];
    try {
      allProducts = await getAllProducts();
    } catch (_) {
      return null;
    }

    if (category != null && category.isNotEmpty) {
      allProducts = allProducts.where((item) => item.category == category).toList();
    }

    final exactAllMatch = _findExactProductMatch(allProducts, normalizedLabel);
    if (exactAllMatch != null) {
      return exactAllMatch;
    }

    return _pickBestProductMatch(allProducts, normalizedLabel);
  }


  Future<NutritionScanResult> recognizeNutritionLabel({
    required String name,
    required String category,
    required double grSugarContent,
    required double netWeight,
    String? scanSource,
    String? image,
    String? rawText,
    XFile? productImageFile,
  }) async {
    if (productImageFile != null) {
      if (kIsWeb) {
        final bytes = await productImageFile.readAsBytes();
        final base64Image = base64Encode(bytes);
        final payload = <String, dynamic>{
          'name': name.trim(),
          'category': category,
          'gr_sugar_content': grSugarContent,
          'net_weight': netWeight,
          'image': image,
          'raw_text': rawText,
          'scan_source': scanSource,
          'product_image_base64': 'data:image/jpeg;base64,$base64Image',
        };

        final map = await _post('/api/products/recognize-nutrition-label', data: payload);
        final envelope = ApiEnvelope<NutritionScanResult>.fromJson(
          map,
          (raw) => NutritionScanResult.fromJson(
            (raw ?? <String, dynamic>{}) as Map<String, dynamic>,
          ),
        );
        final data = envelope.data;
        if (data == null) {
          throw Exception('Produk dari label gizi tidak berhasil diproses.');
        }
        return data;
      }

      final filename = productImageFile.name.isNotEmpty ? productImageFile.name : 'product_image.jpg';
      final MultipartFile imageMultipart;
      imageMultipart = await MultipartFile.fromFile(productImageFile.path, filename: filename);

      final payload = FormData.fromMap({
        'name': name.trim(),
        'category': category,
        'gr_sugar_content': grSugarContent,
        'net_weight': netWeight,
        'image': image,
        'raw_text': rawText,
        'scan_source': scanSource,
        'product_image': imageMultipart,
      });

      final map = await _postWithTimeout(
        '/api/products/recognize-nutrition-label',
        data: payload,
        connectTimeout: const Duration(seconds: 20),
        sendTimeout: const Duration(seconds: 120),
        receiveTimeout: const Duration(seconds: 180),
      );
      final envelope = ApiEnvelope<NutritionScanResult>.fromJson(
        map,
        (raw) => NutritionScanResult.fromJson(
          (raw ?? <String, dynamic>{}) as Map<String, dynamic>,
        ),
      );
      final data = envelope.data;
      if (data == null) {
        throw Exception('Produk dari label gizi tidak berhasil diproses.');
      }
      return data;
    }

    final payload = <String, dynamic>{
      'name': name.trim(),
      'category': category,
      'gr_sugar_content': grSugarContent,
      'net_weight': netWeight,
      'image': image,
      'raw_text': rawText,
    };
    if (scanSource != null && scanSource.isNotEmpty) {
      payload['scan_source'] = scanSource;
    }

    final map = await _post('/api/products/recognize-nutrition-label', data: payload);
    final envelope = ApiEnvelope<NutritionScanResult>.fromJson(
      map,
      (raw) => NutritionScanResult.fromJson(
        (raw ?? <String, dynamic>{}) as Map<String, dynamic>,
      ),
    );
    final data = envelope.data;
    if (data == null) {
      throw Exception('Produk dari label gizi tidak berhasil diproses.');
    }
    return data;
  }

  Future<List<ArticleItem>> getArticles() async {
    final map = await _get('/api/articles');
    final envelope = ApiEnvelope<List<ArticleItem>>.fromJson(
      map,
      (raw) => (raw as List<dynamic>? ?? <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(ArticleItem.fromJson)
          .toList(),
    );
    return envelope.data ?? <ArticleItem>[];
  }

  Future<ArticleDetailData> getArticleDetail(int id) async {
    final map = await _get('/api/articles/$id');
    final envelope = ApiEnvelope<ArticleDetailData>.fromJson(
      map,
      (raw) {
        final body = (raw ?? <String, dynamic>{}) as Map<String, dynamic>;
        final article = ArticleItem.fromJson(
          (body['article'] ?? <String, dynamic>{}) as Map<String, dynamic>,
        );
        final recommendations = ((body['recommended_articles'] as List<dynamic>?) ?? <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(ArticleItem.fromJson)
            .toList();
        return ArticleDetailData(
          article: article,
          recommendedArticles: recommendations,
        );
      },
    );
    final data = envelope.data;
    if (data == null) throw Exception('Detail artikel tidak ditemukan');
    return data;
  }

  Future<NutritionLabelDetectionResult> detectNutritionLabelFromFile(XFile imageFile) async {
    final filename = imageFile.name.isNotEmpty ? imageFile.name : 'nutrition_image.jpg';
    final MultipartFile imageMultipart;
    if (kIsWeb) {
      final bytes = await imageFile.readAsBytes();
      imageMultipart = MultipartFile.fromBytes(bytes, filename: filename);
    } else {
      imageMultipart = await MultipartFile.fromFile(imageFile.path, filename: filename);
    }

    final form = FormData.fromMap({'image': imageMultipart});
    final map = await _postWithTimeout(
      '/api/products/detect-nutrition-image',
      data: form,
      connectTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 120),
      receiveTimeout: const Duration(seconds: 180),
    );
    final envelope = ApiEnvelope<NutritionLabelDetectionResult>.fromJson(
      map,
      (raw) => NutritionLabelDetectionResult.fromJson(
        (raw ?? <String, dynamic>{}) as Map<String, dynamic>,
      ),
    );
    final data = envelope.data;
    if (data == null) {
      throw Exception('Gagal membaca gambar label gizi.');
    }
    return data;
  }

  Future<NutritionLabelDetectionResult> detectProductPackageFromFile(XFile imageFile) async {
    final filename = imageFile.name.isNotEmpty ? imageFile.name : 'package_image.jpg';
    final MultipartFile imageMultipart;
    if (kIsWeb) {
      final bytes = await imageFile.readAsBytes();
      imageMultipart = MultipartFile.fromBytes(bytes, filename: filename);
    } else {
      imageMultipart = await MultipartFile.fromFile(imageFile.path, filename: filename);
    }

    final form = FormData.fromMap({'image': imageMultipart});
    final map = await _postWithTimeout(
      '/api/products/detect-package-image',
      data: form,
      connectTimeout: const Duration(seconds: 8),
      sendTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 20),
    );
    final envelope = ApiEnvelope<NutritionLabelDetectionResult>.fromJson(
      map,
      (raw) => NutritionLabelDetectionResult.fromJson(
        (raw ?? <String, dynamic>{}) as Map<String, dynamic>,
      ),
    );
    final data = envelope.data;
    if (data == null) {
      throw Exception('Gagal membaca foto kemasan produk.');
    }
    return data;
  }

  Future<NutritionLabelDetectionResult> detectCompleteFromFiles({
    required XFile packageImageFile,
    required XFile nutritionImageFile,
  }) async {
    final packageFilename = packageImageFile.name.isNotEmpty ? packageImageFile.name : 'package_image.jpg';
    final nutritionFilename = nutritionImageFile.name.isNotEmpty ? nutritionImageFile.name : 'nutrition_image.jpg';

    final MultipartFile packageMultipart;
    final MultipartFile nutritionMultipart;
    if (kIsWeb) {
      final packageBytes = await packageImageFile.readAsBytes();
      final nutritionBytes = await nutritionImageFile.readAsBytes();
      packageMultipart = MultipartFile.fromBytes(packageBytes, filename: packageFilename);
      nutritionMultipart = MultipartFile.fromBytes(nutritionBytes, filename: nutritionFilename);
    } else {
      packageMultipart = await MultipartFile.fromFile(packageImageFile.path, filename: packageFilename);
      nutritionMultipart = await MultipartFile.fromFile(nutritionImageFile.path, filename: nutritionFilename);
    }

    final form = FormData.fromMap({
      'package_image': packageMultipart,
      'nutrition_image': nutritionMultipart,
    });

    final map = await _postWithTimeout(
      '/api/products/detect-complete-image',
      data: form,
      connectTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 180),
      receiveTimeout: const Duration(seconds: 240),
    );

    final envelope = ApiEnvelope<NutritionLabelDetectionResult>.fromJson(
      map,
      (raw) => NutritionLabelDetectionResult.fromJson(
        (raw ?? <String, dynamic>{}) as Map<String, dynamic>,
      ),
    );
    final data = envelope.data;
    if (data == null) {
      throw Exception('Gagal membaca foto kemasan + label gizi.');
    }
    return data;
  }


  Future<NutritionLabelDetectionResult> detectNutritionLabelFromBytes(
    Uint8List bytes, {
    String filename = 'captured_nutrition.jpg',
  }) async {
    final form = FormData.fromMap({
      'image': MultipartFile.fromBytes(bytes, filename: filename),
    });
    final map = await _postWithTimeout(
      '/api/products/detect-nutrition-image',
      data: form,
      connectTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 120),
      receiveTimeout: const Duration(seconds: 180),
    );
    final envelope = ApiEnvelope<NutritionLabelDetectionResult>.fromJson(
      map,
      (raw) => NutritionLabelDetectionResult.fromJson(
        (raw ?? <String, dynamic>{}) as Map<String, dynamic>,
      ),
    );
    final data = envelope.data;
    if (data == null) {
      throw Exception('Gagal membaca gambar label gizi.');
    }
    return data;
  }


  Future<ProductDetail> getProductDetail(int id) async {
    final map = await _get('/api/products/$id');
    final envelope = ApiEnvelope<ProductDetail>.fromJson(map, (raw) => ProductDetail.fromJson(raw as Map<String, dynamic>));
    final data = envelope.data;
    if (data == null) throw Exception('Detail produk tidak ditemukan');
    return data;
  }

  Future<List<ProductItem>> getRecommendations(int productId) async {
    final map = await _get('/api/recommendation/$productId');
    final envelope = ApiEnvelope<List<ProductItem>>.fromJson(
      map,
      (raw) => (raw as List<dynamic>? ?? <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(ProductItem.fromJson)
          .toList(),
    );
    return envelope.data ?? <ProductItem>[];
  }

  Future<void> saveSearchProduct(int productId) async {
    await _post('/api/user-search-history-product', data: {'product_id': productId});
  }

  Future<void> consumeProduct({required int productId, int percentageConsumed = 1}) async {
    await _post('/api/user-consumption', data: {
      'product_id': productId,
      'percentage_consumed': percentageConsumed,
    });
  }

  Future<SnackBoxStatus> activateSnackBox({String? deviceId}) async {
    final payload = <String, dynamic>{};
    final resolvedDeviceId = (deviceId ?? _snackBoxDeviceId).trim();
    if (resolvedDeviceId.isNotEmpty) {
      payload['device_id'] = resolvedDeviceId;
    }

    final map = await _post('/api/snack-box/activate', data: payload);
    final envelope = ApiEnvelope<SnackBoxStatus>.fromJson(
      map,
      (raw) => SnackBoxStatus.fromJson((raw ?? <String, dynamic>{}) as Map<String, dynamic>),
    );
    final data = envelope.data;
    if (data == null) {
      throw Exception('Status Smart Snack Box tidak ditemukan.');
    }
    return data;
  }

  Future<SnackBoxStatus> getSnackBoxStatus({String? deviceId}) async {
    final queryParameters = <String, dynamic>{};
    final resolvedDeviceId = (deviceId ?? _snackBoxDeviceId).trim();
    if (resolvedDeviceId.isNotEmpty) {
      queryParameters['device_id'] = resolvedDeviceId;
    }

    final map = await _get('/api/snack-box/status', queryParameters: queryParameters);
    final envelope = ApiEnvelope<SnackBoxStatus>.fromJson(
      map,
      (raw) => SnackBoxStatus.fromJson((raw ?? <String, dynamic>{}) as Map<String, dynamic>),
    );
    final data = envelope.data;
    if (data == null) {
      throw Exception('Status Smart Snack Box tidak tersedia.');
    }
    return data;
  }

  Future<void> deleteConsumedProduct({required int consumptionRecordId}) async {
    try {
      await _requestWithFailover(
        () => _dio.delete<Map<String, dynamic>>('/api/user-consumption/$consumptionRecordId'),
      );
    } on DioException catch (e) {
      throw Exception(_resolveErrorMessage(e));
    }
  }

  Future<int> deleteAllConsumedProducts() async {
    final map = await _delete('/api/user-consumption');
    final envelope = ApiEnvelope<int>.fromJson(
      map,
      (raw) {
        if (raw is Map<String, dynamic>) {
          return int.tryParse((raw['deleted_count'] ?? 0).toString()) ?? 0;
        }
        return 0;
      },
    );
    return envelope.data ?? 0;
  }

  Future<List<ProductItem>> getSearchHistory() async {
    final map = await _get('/api/user-search-history-product');
    final envelope = ApiEnvelope<List<ProductItem>>.fromJson(
      map,
      (raw) => (raw as List<dynamic>? ?? <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(ProductItem.fromJson)
          .toList(),
    );
    return envelope.data ?? <ProductItem>[];
  }

  Future<List<ProductItem>> getConsumedProducts() async {
    final map = await _get('/api/user-consumption');
    final envelope = ApiEnvelope<List<ProductItem>>.fromJson(
      map,
      (raw) => (raw as List<dynamic>? ?? <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(ProductItem.fromJson)
          .toList(),
    );
    return envelope.data ?? <ProductItem>[];
  }

  Future<double> getTodaySugar() async {
    final map = await _get('/api/report/user/sugar/today');
    final envelope = ApiEnvelope<double>.fromJson(map, (raw) {
      if (raw == null) return 0;
      return double.tryParse(raw.toString()) ?? 0;
    });
    return envelope.data ?? 0;
  }

  Future<Map<String, dynamic>> checkHeartRate() async {
    return _postWithTimeout(
      '/api/health-monitoring/check-heart-rate',
      connectTimeout: const Duration(seconds: 120),
      sendTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 180),
    );
  }

  Future<Map<String, dynamic>> checkBodyTemperature({required int checkId}) async {
    return _postWithTimeout(
      '/api/health-monitoring/check-body-temperature',
      data: {'check_id': checkId},
      connectTimeout: const Duration(seconds: 60),
      sendTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 60),
    );
  }

  Future<HealthMonitoringRecord> analyzeHealthMonitoring({
    required int checkId,
    required int age,
    required String gender,
    required double heightCm,
    required double weightKg,
    required double bmi,
  }) async {
    final map = await _post('/api/health-monitoring/analyze', data: {
      'check_id': checkId,
      'age': age,
      'gender': gender,
      'height_cm': heightCm,
      'weight_kg': weightKg,
      'bmi': bmi,
    });
    final envelope = ApiEnvelope<HealthMonitoringRecord>.fromJson(
      map,
      (raw) => HealthMonitoringRecord.fromJson((raw ?? <String, dynamic>{}) as Map<String, dynamic>),
    );
    final data = envelope.data;
    if (data == null) {
      throw Exception('Gagal memproses monitoring kesehatan.');
    }
    return data;
  }

  Future<List<HealthMonitoringRecord>> getHealthMonitoringHistory() async {
    final map = await _get('/api/health-monitoring/history');
    final envelope = ApiEnvelope<List<HealthMonitoringRecord>>.fromJson(
      map,
      (raw) => (raw as List<dynamic>? ?? <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(HealthMonitoringRecord.fromJson)
          .toList(),
    );
    return envelope.data ?? <HealthMonitoringRecord>[];
  }

  Future<List<ReportListItem>> getWeeklyReports() async {
    final map = await _get('/api/report/user/sugar/weekly-list');
    return _parseReportList(map);
  }

  Future<List<ReportListItem>> getMonthlyReports() async {
    final map = await _get('/api/report/user/sugar/monthly-list');
    return _parseReportList(map);
  }

  Future<List<ReportListItem>> getYearlyReports() async {
    final map = await _get('/api/report/user/sugar/yearly-list');
    return _parseReportList(map);
  }

  Future<List<ReportListItem>> searchReports(String query) async {
    final map = await _get('/api/report/user/sugar/search', queryParameters: {'query': query});
    return _parseReportList(map);
  }

  Future<List<WeeklyChartPoint>> getWeeklyChart(int reportId) async {
    final map = await _get('/api/report/user/consumption/$reportId');
    final envelope = ApiEnvelope<List<WeeklyChartPoint>>.fromJson(
      map,
      (raw) => (raw as List<dynamic>? ?? <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(WeeklyChartPoint.fromJson)
          .toList(),
    );
    return envelope.data ?? <WeeklyChartPoint>[];
  }

  Future<List<MonthlyChartPoint>> getMonthlyChart({required String month, required int year}) async {
    final map = await _get(
      '/api/report/user/monthly-consumption',
      queryParameters: {'month': month, 'year': year},
    );
    final envelope = ApiEnvelope<List<MonthlyChartPoint>>.fromJson(
      map,
      (raw) => (raw as List<dynamic>? ?? <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(MonthlyChartPoint.fromJson)
          .toList(),
    );
    return envelope.data ?? <MonthlyChartPoint>[];
  }

  Future<List<YearlyChartPoint>> getYearlyChart({required int year}) async {
    final map = await _get('/api/report/user/yearly-consumption', queryParameters: {'year': year});
    final envelope = ApiEnvelope<List<YearlyChartPoint>>.fromJson(
      map,
      (raw) => (raw as List<dynamic>? ?? <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(YearlyChartPoint.fromJson)
          .toList(),
    );
    return envelope.data ?? <YearlyChartPoint>[];
  }

  Future<void> suggestProduct({
    required String name,
    required String category,
    required double grSugarContent,
    required double netWeight,
    required double servingsPerPackage,
    required double servingSizeMl,
    required XFile imageFile,
  }) async {
    final filename = imageFile.name.isNotEmpty ? imageFile.name : 'product_image.jpg';
    final MultipartFile imageMultipart;
    if (kIsWeb) {
      final bytes = await imageFile.readAsBytes();
      imageMultipart = MultipartFile.fromBytes(bytes, filename: filename);
    } else {
      imageMultipart = await MultipartFile.fromFile(imageFile.path, filename: filename);
    }

    final form = FormData.fromMap({
      'name': name,
      'category': category,
      'gr_sugar_content': grSugarContent,
      'net_weight': netWeight,
      'servings_per_package': servingsPerPackage,
      'serving_size_ml': servingSizeMl,
      'image': imageMultipart,
    });

    await _post('/api/suggested-products', data: form);
  }

  Future<int?> classifyProductByImage(XFile imageFile) async {
    final filename = imageFile.name.isNotEmpty ? imageFile.name : 'captured_image.jpg';
    final MultipartFile imageMultipart;
    if (kIsWeb) {
      final bytes = await imageFile.readAsBytes();
      imageMultipart = MultipartFile.fromBytes(bytes, filename: filename);
    } else {
      imageMultipart = await MultipartFile.fromFile(imageFile.path, filename: filename);
    }

    final form = FormData.fromMap({'image': imageMultipart});

    try {
      final response = await _requestWithFailover(
        () => _dio.post<Map<String, dynamic>>(
          '/api/classify-product',
          data: form,
          options: Options(
            connectTimeout: const Duration(seconds: 20),
            sendTimeout: const Duration(seconds: 120),
            receiveTimeout: const Duration(seconds: 180),
          ),
        ),
      );
      final map = _extractMap(response.data);
      final data = map['data'];
      if (data is! Map<String, dynamic>) {
        return null;
      }

      final rawId = data['predicted_product_id'] ?? data['product_id'];
      if (rawId == null) return null;
      if (rawId is int) return rawId;
      return int.tryParse(rawId.toString());
    } on DioException catch (e) {
      if (e.response?.statusCode == 422) {
        return null;
      }
      throw Exception(_resolveErrorMessage(e));
    }
  }

  Future<Map<String, dynamic>> _get(String path, {Map<String, dynamic>? queryParameters}) async {
    try {
      final response = await _requestWithFailover(
        () => _dio.get<Map<String, dynamic>>(path, queryParameters: queryParameters),
      );
      return _extractMap(response.data);
    } on DioException catch (e) {
      throw Exception(_resolveErrorMessage(e));
    }
  }

  Future<Map<String, dynamic>> _post(String path, {dynamic data}) async {
    try {
      final response = await _requestWithFailover(
        () => _dio.post<Map<String, dynamic>>(path, data: data),
      );
      return _extractMap(response.data);
    } on DioException catch (e) {
      throw Exception(_resolveErrorMessage(e));
    }
  }

  Future<Map<String, dynamic>> _postWithTimeout(
    String path, {
    dynamic data,
    required Duration connectTimeout,
    required Duration sendTimeout,
    required Duration receiveTimeout,
  }) async {
    try {
      final response = await _requestWithFailover(
        () => _dio.post<Map<String, dynamic>>(
          path,
          data: data,
          options: Options(
            connectTimeout: connectTimeout,
            sendTimeout: sendTimeout,
            receiveTimeout: receiveTimeout,
          ),
        ),
      );
      return _extractMap(response.data);
    } on DioException catch (e) {
      throw Exception(_resolveErrorMessage(e));
    }
  }

  Future<Map<String, dynamic>> _patch(String path, {dynamic data}) async {
    try {
      final response = await _requestWithFailover(
        () => _dio.patch<Map<String, dynamic>>(path, data: data),
      );
      return _extractMap(response.data);
    } on DioException catch (e) {
      throw Exception(_resolveErrorMessage(e));
    }
  }

  Future<Map<String, dynamic>> _delete(String path) async {
    try {
      final response = await _requestWithFailover(
        () => _dio.delete<Map<String, dynamic>>(path),
      );
      return _extractMap(response.data);
    } on DioException catch (e) {
      throw Exception(_resolveErrorMessage(e));
    }
  }

  Future<Response<Map<String, dynamic>>> _requestWithFailover(
    Future<Response<Map<String, dynamic>>> Function() request,
  ) async {
    DioException? lastError;

    for (var i = 0; i < _baseCandidates.length; i++) {
      final idx = (_currentBaseIndex + i) % _baseCandidates.length;
      final base = _baseCandidates[idx];
      _dio.options.baseUrl = base;

      try {
        final response = await request();
        _currentBaseIndex = idx;
        return response;
      } on DioException catch (e) {
        lastError = e;
        if (!_isConnectionIssue(e)) {
          rethrow;
        }
      }
    }

    throw lastError ??
        DioException(
          requestOptions: RequestOptions(path: ''),
          type: DioExceptionType.unknown,
          error: 'Unknown network error',
        );
  }

  Map<String, dynamic> _extractMap(Map<String, dynamic>? data) {
    if (data == null) {
      throw Exception('Respon API kosong');
    }

    final success = data['success'] == true;
    if (!success) {
      final message = (data['message'] ?? 'Permintaan gagal').toString();
      throw Exception(message);
    }

    _normalizePayloadImageUrls(data);
    return data;
  }

  void _normalizePayloadImageUrls(dynamic node) {
    if (node is Map<String, dynamic>) {
      for (final entry in node.entries) {
        final key = entry.key.toLowerCase();
        final value = entry.value;
        if ((key == 'image' || key == 'product_image') && value is String) {
          node[entry.key] = _resolveMediaUrl(value);
          continue;
        }
        _normalizePayloadImageUrls(value);
      }
      return;
    }

    if (node is List) {
      for (final item in node) {
        _normalizePayloadImageUrls(item);
      }
    }
  }

  String _resolveMediaUrl(String rawValue) {
    final raw = rawValue.trim();
    if (raw.isEmpty) return raw;

    final base = Uri.tryParse(_dio.options.baseUrl);
    if (base == null) return raw;

    if (raw.startsWith('/')) {
      return base.resolve(raw).toString();
    }

    if (raw.startsWith('storage/')) {
      return base.resolve('/$raw').toString();
    }

    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasScheme) return raw;

    final isLocalLoopback = uri.host == '127.0.0.1' || uri.host == 'localhost';
    if (!isLocalLoopback) return raw;

    if (base.host == '127.0.0.1' || base.host == 'localhost') {
      return raw;
    }

    return uri.replace(
      scheme: base.scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
    ).toString();
  }

  String _resolveErrorMessage(DioException exception) {
    final statusCode = exception.response?.statusCode;

    if (kDebugMode) {
      debugPrint(
        '[ApiService] Request failed baseUrl=${_dio.options.baseUrl} '
        'path=${exception.requestOptions.path} status=$statusCode type=${exception.type}',
      );
    }

    if (_isConnectionIssue(exception)) {
      if (exception.type == DioExceptionType.receiveTimeout) {
        return 'Waktu tunggu sensor habis. Pastikan ESP32 merespons endpoint detak/suhu dan ulangi pengecekan.';
      }

      if (kIsWeb) {
        return 'Tidak dapat terhubung ke API lokal (${_dio.options.baseUrl}). '
            'Pastikan backend aktif (Docker: `docker-compose up -d --build backend label-gizi-service`) '
            'atau Laravel lokal: `php artisan serve --host=127.0.0.1 --port=8000`.';
      }

      return 'Tidak dapat terhubung ke API (${_dio.options.baseUrl}). '
          'Jika pakai HP fisik + backend lokal, jalankan `adb reverse tcp:8000 tcp:8000` '
          'atau jalankan app dengan `--dart-define=API_BASE_URL=http://IP_LAPTOP:8000`.';
    }

    final responseData = exception.response?.data;
    if (responseData is Map<String, dynamic>) {
      final message = responseData['message'];
      if (message != null && message.toString().isNotEmpty) {
        final errors = responseData['errors'];
        if (errors is Map<String, dynamic>) {
          final imageErrors = errors['image'];
          if (imageErrors is List && imageErrors.isNotEmpty) {
            return imageErrors.first.toString();
          }
          final productImageErrors = errors['product_image'];
          if (productImageErrors is List && productImageErrors.isNotEmpty) {
            return productImageErrors.first.toString();
          }
          for (final value in errors.values) {
            if (value is List && value.isNotEmpty) {
              return value.first.toString();
            }
          }
        }
        return message.toString();
      }
    }
    if (responseData is String && responseData.trim().startsWith('{')) {
      try {
        final decoded = jsonDecode(responseData);
        if (decoded is Map<String, dynamic>) {
          final message = decoded['message'];
          if (message != null && message.toString().isNotEmpty) {
            return message.toString();
          }
        }
      } catch (_) {
        // Ignore JSON parse failure.
      }
    }

    if (statusCode != null) {
      if (statusCode == 401) {
        return 'Sesi login berakhir. Silakan login ulang.';
      }
      if (statusCode == 403) {
        return 'Anda tidak memiliki akses untuk aksi ini.';
      }
      if (statusCode == 422) {
        return 'Data yang dikirim tidak valid. Cek lagi input Anda.';
      }
      if (statusCode >= 500) {
        return 'Server backend sedang bermasalah ($statusCode). Coba lagi sebentar.';
      }
    }

    if (exception.message != null && exception.message!.isNotEmpty) {
      return exception.message!;
    }

    return 'Terjadi kesalahan jaringan.';
  }

  bool _isConnectionIssue(DioException exception) {
    return exception.type == DioExceptionType.connectionError ||
        exception.type == DioExceptionType.connectionTimeout ||
        exception.type == DioExceptionType.receiveTimeout ||
        exception.type == DioExceptionType.sendTimeout;
  }

  List<ProductItem> _parseProductList(Map<String, dynamic> map) {
    final envelope = ApiEnvelope<List<ProductItem>>.fromJson(
      map,
      (raw) => (raw as List<dynamic>? ?? <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(ProductItem.fromJson)
          .toList(),
    );
    return envelope.data ?? <ProductItem>[];
  }

  List<ReportListItem> _parseReportList(Map<String, dynamic> map) {
    final envelope = ApiEnvelope<List<ReportListItem>>.fromJson(
      map,
      (raw) => (raw as List<dynamic>? ?? <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(ReportListItem.fromJson)
          .toList(),
    );
    return envelope.data ?? <ReportListItem>[];
  }

  ProductItem? _findExactProductMatch(List<ProductItem> products, String normalizedLabel) {
    for (final product in products) {
      if (_normalizeProductLookupText(product.name) == normalizedLabel) {
        return product;
      }
    }
    return null;
  }

  ProductItem? _pickBestProductMatch(List<ProductItem> products, String normalizedLabel) {
    final labelTokens = _lookupTokens(normalizedLabel);
    if (products.isEmpty || labelTokens.isEmpty) {
      return null;
    }

    ProductItem? best;
    var bestScore = double.negativeInfinity;

    for (final product in products) {
      final normalizedProduct = _normalizeProductLookupText(product.name);
      if (normalizedProduct.isEmpty) {
        continue;
      }

      final productTokens = _lookupTokens(normalizedProduct);
      var score = 0.0;

      if (normalizedProduct == normalizedLabel) {
        score += 120;
      }
      if (normalizedProduct.contains(normalizedLabel) && normalizedLabel.length >= 4) {
        score += 45;
      }
      if (normalizedLabel.contains(normalizedProduct) && normalizedProduct.length >= 4) {
        score += 40;
      }

      final nameSimilarity = _stringSimilarity(normalizedLabel, normalizedProduct);
      score += nameSimilarity * 40;

      final overlap = labelTokens.intersection(productTokens).length;
      score += overlap * 14;

      final unmatchedLabel = labelTokens.length - overlap;
      final unmatchedProduct = productTokens.length - overlap;
      score -= unmatchedLabel * 2;
      score -= unmatchedProduct * 2;

      final firstLabelToken = labelTokens.isNotEmpty ? labelTokens.first : '';
      final firstProductToken = productTokens.isNotEmpty ? productTokens.first : '';
      if (firstLabelToken.isNotEmpty &&
          firstProductToken.isNotEmpty &&
          _stringSimilarity(firstLabelToken, firstProductToken) >= 0.75) {
        score += 18;
      }

      if (score > bestScore) {
        bestScore = score;
        best = product;
      }
    }

    if (bestScore < 10) {
      return null;
    }
    return best;
  }

  String _normalizeProductLookupText(String value) {
    return value
        .replaceAll(RegExp(r'\(\d+\)'), '')
        .replaceAll(RegExp(r'\bcopy\b', caseSensitive: false), '')
        .toLowerCase()
        .replaceAll('&', ' and ')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Set<String> _lookupTokens(String value) {
    return value.split(' ').where((token) => token.length >= 3).toSet();
  }

  double _stringSimilarity(String left, String right) {
    if (left.isEmpty || right.isEmpty) return 0;
    if (left == right) return 1;

    final distance = _levenshteinDistance(left, right);
    final maxLength = left.length > right.length ? left.length : right.length;
    if (maxLength == 0) return 0;

    return 1 - (distance / maxLength);
  }

  int _levenshteinDistance(String left, String right) {
    if (left == right) return 0;
    if (left.isEmpty) return right.length;
    if (right.isEmpty) return left.length;

    var previous = List<int>.generate(right.length + 1, (index) => index);
    var current = List<int>.filled(right.length + 1, 0);

    for (var i = 1; i <= left.length; i++) {
      current[0] = i;
      for (var j = 1; j <= right.length; j++) {
        final substitutionCost = left.codeUnitAt(i - 1) == right.codeUnitAt(j - 1) ? 0 : 1;
        final deletion = previous[j] + 1;
        final insertion = current[j - 1] + 1;
        final substitution = previous[j - 1] + substitutionCost;
        current[j] = deletion < insertion
            ? (deletion < substitution ? deletion : substitution)
            : (insertion < substitution ? insertion : substitution);
      }
      final temp = previous;
      previous = current;
      current = temp;
    }

    return previous[right.length];
  }
}
