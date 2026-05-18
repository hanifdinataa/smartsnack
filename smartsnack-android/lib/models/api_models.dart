class ApiEnvelope<T> {
  const ApiEnvelope({
    required this.code,
    required this.success,
    required this.message,
    this.data,
  });

  final int code;
  final bool success;
  final String message;
  final T? data;

  factory ApiEnvelope.fromJson(
    Map<String, dynamic> json,
    T Function(dynamic raw)? parser,
  ) {
    return ApiEnvelope<T>(
      code: _asInt(json['code']),
      success: json['success'] == true,
      message: (json['message'] ?? '').toString(),
      data: parser == null ? json['data'] as T? : parser(json['data']),
    );
  }
}

class UserModel {
  const UserModel({
    required this.id,
    required this.name,
    required this.email,
  });

  final int id;
  final String name;
  final String email;

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: _asInt(json['id']),
      name: (json['name'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
    );
  }
}

class AuthData {
  const AuthData({
    required this.user,
    required this.token,
  });

  final UserModel user;
  final String token;

  factory AuthData.fromJson(Map<String, dynamic> json) {
    return AuthData(
      user: UserModel.fromJson((json['user'] ?? <String, dynamic>{}) as Map<String, dynamic>),
      token: (json['token'] ?? '').toString(),
    );
  }
}

class ProductItem {
  const ProductItem({
    required this.id,
    required this.name,
    required this.image,
    required this.sugarGrade,
    required this.grSugarContent,
    required this.netWeight,
    this.category = '',
    this.servingSizeMl = 0,
    this.amountConsumed = '',
    this.date = '',
    this.consumptionRecordId,
  });

  final int id;
  final String name;
  final String image;
  final String sugarGrade;
  final double grSugarContent;
  final String netWeight;
  final String category;
  final double servingSizeMl;
  final String amountConsumed;
  final String date;
  final int? consumptionRecordId;

  factory ProductItem.fromJson(Map<String, dynamic> json) {
    final dynamic productId = json['product_id'];
    final dynamic idRaw = json['id'];
    return ProductItem(
      id: _asInt(productId ?? idRaw),
      name: (json['name'] ?? json['product_name'] ?? '').toString(),
      image: (json['image'] ?? json['product_image'] ?? '').toString(),
      sugarGrade: (json['sugar_grade'] ?? '').toString(),
      grSugarContent: _asDouble(json['gr_sugar_content'] ?? json['gr_sugar_consumed']),
      netWeight: (json['net_weight'] ?? '').toString(),
      category: (json['category'] ?? '').toString(),
      servingSizeMl: _asDouble(json['serving_size_ml']),
      amountConsumed: (json['amountConsumed'] ?? '').toString(),
      date: (json['date'] ?? '').toString(),
      consumptionRecordId: json['id'] == null ? null : _asInt(json['id']),
    );
  }
}

class HealthMonitoringRecord {
  const HealthMonitoringRecord({
    required this.checkId,
    required this.heartRate,
    required this.bodyTemp,
    required this.age,
    required this.gender,
    required this.heightCm,
    required this.weightKg,
    required this.bmi,
    required this.riskDiabetes,
    required this.algorithm,
    this.riskPercent,
    required this.checkedAtIso,
  });

  final int checkId;
  final double heartRate;
  final double bodyTemp;
  final int age;
  final String gender;
  final double heightCm;
  final double weightKg;
  final double bmi;
  final String riskDiabetes;
  final String algorithm;
  final double? riskPercent;
  final String checkedAtIso;

  factory HealthMonitoringRecord.fromJson(Map<String, dynamic> json) {
    return HealthMonitoringRecord(
      checkId: _asInt(json['check_id']),
      heartRate: _asDouble(json['heart_rate']),
      bodyTemp: _asDouble(json['body_temp']),
      age: _asInt(json['age']),
      gender: (json['gender'] ?? 'Male').toString(),
      heightCm: _asDouble(json['height_cm']),
      weightKg: _asDouble(json['weight_kg']),
      bmi: _asDouble(json['bmi']),
      riskDiabetes: (json['risk_diabetes'] ?? 'TIDAK').toString().toUpperCase(),
      algorithm: (json['algorithm'] ?? '').toString(),
      riskPercent: _asNullableDouble(json['risk_percent'] ?? json['probability_diabetes'] ?? json['probability']),
      checkedAtIso: (json['checked_at'] ?? DateTime.now().toIso8601String()).toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'check_id': checkId,
      'heart_rate': heartRate,
      'body_temp': bodyTemp,
      'age': age,
      'gender': gender,
      'height_cm': heightCm,
      'weight_kg': weightKg,
      'bmi': bmi,
      'risk_diabetes': riskDiabetes,
      'algorithm': algorithm,
      'risk_percent': riskPercent,
      'checked_at': checkedAtIso,
    };
  }
}

class SnackBoxStatus {
  const SnackBoxStatus({
    required this.deviceId,
    required this.riskDiabetes,
    required this.sugarLimit,
    required this.todaySugar,
    required this.remainingSugar,
    required this.canConsume,
    required this.canOpenServo,
    required this.reason,
    required this.message,
    required this.isActiveUser,
  });

  final String deviceId;
  final String riskDiabetes;
  final double sugarLimit;
  final double todaySugar;
  final double remainingSugar;
  final bool canConsume;
  final bool canOpenServo;
  final String reason;
  final String message;
  final bool isActiveUser;

  factory SnackBoxStatus.fromJson(Map<String, dynamic> json) {
    return SnackBoxStatus(
      deviceId: (json['device_id'] ?? '').toString(),
      riskDiabetes: (json['risk_diabetes'] ?? 'UNKNOWN').toString().toUpperCase(),
      sugarLimit: _asDouble(json['sugar_limit']),
      todaySugar: _asDouble(json['today_sugar']),
      remainingSugar: _asDouble(json['remaining_sugar']),
      canConsume: json['can_consume'] == true,
      canOpenServo: json['can_open_servo'] == true,
      reason: (json['reason'] ?? '').toString(),
      message: (json['message'] ?? '').toString(),
      isActiveUser: json['is_active_user'] == true,
    );
  }
}

class ProductVariant {
  const ProductVariant({required this.id, required this.name});

  final int id;
  final String name;

  factory ProductVariant.fromJson(Map<String, dynamic> json) {
    return ProductVariant(
      id: _asInt(json['id']),
      name: (json['name'] ?? '').toString(),
    );
  }
}

class ProductDetail {
  const ProductDetail({
    required this.id,
    required this.name,
    required this.image,
    required this.sugarGrade,
    required this.grSugarContent,
    required this.category,
    required this.netWeight,
    required this.servingsPerPackage,
    required this.information,
    required this.variants,
  });

  final int id;
  final String name;
  final String image;
  final String sugarGrade;
  final double grSugarContent;
  final String category;
  final double netWeight;
  final String servingsPerPackage;
  final String information;
  final List<ProductVariant> variants;

  factory ProductDetail.fromJson(Map<String, dynamic> json) {
    final rawVariants = (json['varians'] as List<dynamic>? ?? <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(ProductVariant.fromJson)
        .toList();

    return ProductDetail(
      id: _asInt(json['id']),
      name: (json['name'] ?? '').toString(),
      image: (json['image'] ?? '').toString(),
      sugarGrade: (json['sugar_grade'] ?? '').toString(),
      grSugarContent: _asDouble(json['gr_sugar_content']),
      category: (json['category'] ?? '').toString(),
      netWeight: _asDouble(json['net_weight']),
      servingsPerPackage: (json['servings_per_package'] ?? '').toString(),
      information: (json['information'] ?? '').toString(),
      variants: rawVariants,
    );
  }
}

class NutritionScanResult {
  const NutritionScanResult({
    required this.productId,
    required this.productName,
    required this.category,
    required this.sugarGrade,
    required this.grSugarContent,
    required this.netWeight,
    required this.scanSource,
    required this.matchedExisting,
  });

  final int productId;
  final String productName;
  final String category;
  final String sugarGrade;
  final double grSugarContent;
  final double netWeight;
  final String scanSource;
  final bool matchedExisting;

  factory NutritionScanResult.fromJson(Map<String, dynamic> json) {
    return NutritionScanResult(
      productId: _asInt(json['product_id']),
      productName: (json['product_name'] ?? '').toString(),
      category: (json['category'] ?? '').toString(),
      sugarGrade: (json['sugar_grade'] ?? '').toString(),
      grSugarContent: _asDouble(json['gr_sugar_content']),
      netWeight: _asDouble(json['net_weight']),
      scanSource: (json['scan_source'] ?? '').toString(),
      matchedExisting: _asBool(json['matched_existing']),
    );
  }
}

class NutritionLabelDetectionResult {
  const NutritionLabelDetectionResult({
    required this.name,
    required this.category,
    required this.grSugarContent,
    required this.netWeight,
    required this.rawText,
    required this.labelText,
    required this.productText,
  });

  final String name;
  final String category;
  final double? grSugarContent;
  final double? netWeight;
  final String rawText;
  final String labelText;
  final String productText;

  factory NutritionLabelDetectionResult.fromJson(Map<String, dynamic> json) {
    return NutritionLabelDetectionResult(
      name: (json['name'] ?? '').toString(),
      category: (json['category'] ?? 'food').toString(),
      grSugarContent: json['gr_sugar_content'] == null ? null : _asDouble(json['gr_sugar_content']),
      netWeight: json['net_weight'] == null ? null : _asDouble(json['net_weight']),
      rawText: (json['raw_text'] ?? '').toString(),
      labelText: (json['label_text'] ?? '').toString(),
      productText: (json['product_text'] ?? '').toString(),
    );
  }
}

class ReportListItem {
  const ReportListItem({
    this.id,
    this.month,
    this.year,
    this.report,
    this.weekNumber,
  });

  final int? id;
  final String? month;
  final int? year;
  final String? report;
  final int? weekNumber;

  factory ReportListItem.fromJson(Map<String, dynamic> json) {
    return ReportListItem(
      id: json['id'] == null ? null : _asInt(json['id']),
      month: json['month']?.toString(),
      year: json['year'] == null ? null : _asInt(json['year']),
      report: json['report']?.toString(),
      weekNumber: json['week_number'] == null ? null : _asInt(json['week_number']),
    );
  }
}

class WeeklyChartPoint {
  const WeeklyChartPoint({
    required this.day,
    required this.totalSugar,
    required this.sugarGrade,
  });

  final int day;
  final double totalSugar;
  final String sugarGrade;

  factory WeeklyChartPoint.fromJson(Map<String, dynamic> json) {
    return WeeklyChartPoint(
      day: _asInt(json['day']),
      totalSugar: _asDouble(json['total_sugar']),
      sugarGrade: (json['sugar_grade'] ?? '').toString(),
    );
  }
}

class MonthlyChartPoint {
  const MonthlyChartPoint({
    required this.weekNumber,
    required this.totalSugar,
    required this.sugarGrade,
  });

  final int weekNumber;
  final double totalSugar;
  final String sugarGrade;

  factory MonthlyChartPoint.fromJson(Map<String, dynamic> json) {
    return MonthlyChartPoint(
      weekNumber: _asInt(json['week_number']),
      totalSugar: _asDouble(json['total_sugar']),
      sugarGrade: (json['sugar_grade'] ?? '').toString(),
    );
  }
}

class YearlyChartPoint {
  const YearlyChartPoint({
    required this.month,
    required this.totalSugar,
    required this.sugarGrade,
  });

  final String month;
  final double totalSugar;
  final String sugarGrade;

  factory YearlyChartPoint.fromJson(Map<String, dynamic> json) {
    return YearlyChartPoint(
      month: (json['month'] ?? '').toString(),
      totalSugar: _asDouble(json['total_sugar']),
      sugarGrade: (json['sugar_grade'] ?? '').toString(),
    );
  }
}

class ArticleItem {
  const ArticleItem({
    required this.id,
    required this.title,
    required this.excerpt,
    required this.content,
    required this.image,
    required this.publishedAt,
  });

  final int id;
  final String title;
  final String excerpt;
  final String content;
  final String image;
  final String publishedAt;

  factory ArticleItem.fromJson(Map<String, dynamic> json) {
    return ArticleItem(
      id: _asInt(json['id']),
      title: (json['title'] ?? '').toString(),
      excerpt: (json['excerpt'] ?? '').toString(),
      content: (json['content'] ?? '').toString(),
      image: (json['image'] ?? '').toString(),
      publishedAt: (json['published_at'] ?? '').toString(),
    );
  }
}

class ArticleDetailData {
  const ArticleDetailData({
    required this.article,
    required this.recommendedArticles,
  });

  final ArticleItem article;
  final List<ArticleItem> recommendedArticles;
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is double) return value.toInt();
  return int.tryParse((value ?? '0').toString()) ?? 0;
}

double _asDouble(dynamic value) {
  if (value is double) return value;
  if (value is int) return value.toDouble();
  return double.tryParse((value ?? '0').toString()) ?? 0;
}

bool _asBool(dynamic value) {
  if (value is bool) return value;
  final normalized = (value ?? '').toString().toLowerCase();
  return normalized == 'true' || normalized == '1';
}

double? _asNullableDouble(dynamic value) {
  if (value == null) return null;
  final parsed = double.tryParse(value.toString());
  return parsed;
}
