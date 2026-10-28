import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/food_item.dart';
import '../models/meal_entry.dart';

class NutritionService {
  static const String baseUrl = 'http://localhost:3000/api';

  // Get all dining halls
  static Future<List<String>> getDiningHalls() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/dining-halls'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<String>.from(data['dining_halls'] ?? []);
      } else {
        throw Exception('Failed to load dining halls');
      }
    } catch (e) {
      throw Exception('Network error: ${e.toString()}');
    }
  }

  // Get foods for a dining hall
  static Future<List<FoodItem>> getFoodsForDiningHall(
    String diningHall, {
    String? mealType,
    String? date,
  }) async {
    final result = await getFoodListResult(
      diningHall,
      mealType: mealType,
      date: date,
    );
    return result.foods;
  }

  // Get foods for a dining hall, optionally limited to those that meet the
  // user's dietary restrictions. Also returns why the list is empty, if it is.
  static Future<FoodListResult> getFoodListResult(
    String diningHall, {
    String? mealType,
    String? date,
    int? userId,
    bool applyRestrictions = false,
  }) async {
    try {
      var uri = Uri.parse('$baseUrl/dining-halls/${Uri.encodeComponent(diningHall)}/foods');

      final queryParams = <String, String>{};
      if (mealType != null) queryParams['meal_type'] = mealType;
      if (date != null) queryParams['date'] = date;
      if (applyRestrictions && userId != null) {
        queryParams['user_id'] = userId.toString();
        queryParams['apply_restrictions'] = 'true';
      }

      uri = uri.replace(queryParameters: queryParams);

      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return FoodListResult.fromJson(data, 'foods');
      } else {
        throw Exception('Failed to load foods');
      }
    } catch (e) {
      throw Exception('Network error: ${e.toString()}');
    }
  }

  // Which dining hall best fits the user's restrictions and goal for a meal
  static Future<HallRecommendation> getBestDiningHall(
    int userId,
    String mealType,
  ) async {
    try {
      final uri = Uri.parse('$baseUrl/recommendations/$userId/dining-halls')
          .replace(queryParameters: {'meal_type': mealType});

      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return HallRecommendation.fromJson(json.decode(response.body));
      } else {
        throw Exception('Failed to load dining hall recommendation');
      }
    } catch (e) {
      throw Exception('Network error: ${e.toString()}');
    }
  }

  // Get recommended foods for user. Foods that do not meet the user's dietary
  // restrictions are already removed by the server; 'message' explains an empty list.
  static Future<Map<String, dynamic>> getRecommendations(
    int userId,
    String diningHall, {
    String? mealType,
  }) async {
    try {
      var uri = Uri.parse('$baseUrl/recommendations/$userId');

      final queryParams = <String, String>{'dining_hall': diningHall};
      if (mealType != null) queryParams['meal_type'] = mealType;

      uri = uri.replace(queryParameters: queryParams);

      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'recommendations': (data['recommendations'] as List)
              .map((f) => FoodItem.fromJson(f))
              .toList(),
          'user_target_calories': data['user_target_calories'],
          'goal': data['goal'],
          'count': data['count'],
          'message': data['message'],
          'restrictions_applied': List<String>.from(data['restrictions_applied'] ?? []),
          'unsupported_restrictions': List<String>.from(data['unsupported_restrictions'] ?? []),
        };
      } else {
        throw Exception('Failed to load recommendations');
      }
    } catch (e) {
      throw Exception('Network error: ${e.toString()}');
    }
  }

  // Log a consumed meal
  static Future<MealEntry> logMeal(
    int userId,
    List<FoodItem> foods, {
    String? mealType,
    String? diningHall,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/user/$userId/meals'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'foods': foods.map((f) => f.toJson()).toList(),
          'meal_type': mealType ?? 'Snack',
          'dining_hall': diningHall ?? 'Unknown',
          'consumed_at': DateTime.now().toIso8601String(),
        }),
      );

      if (response.statusCode == 201) {
        final data = json.decode(response.body);
        return MealEntry.fromJson(data['meal']);
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Failed to log meal');
      }
    } catch (e) {
      throw Exception('Network error: ${e.toString()}');
    }
  }

  // Get user's meal history
  static Future<List<MealEntry>> getMealHistory(
    int userId, {
    String? date,
    int? limit,
  }) async {
    try {
      var uri = Uri.parse('$baseUrl/user/$userId/meals');

      final queryParams = <String, String>{};
      if (date != null) queryParams['date'] = date;
      if (limit != null) queryParams['limit'] = limit.toString();

      uri = uri.replace(queryParameters: queryParams);

      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final mealsList = data['meals'] as List;
        return mealsList.map((m) => MealEntry.fromJson(m)).toList();
      } else {
        throw Exception('Failed to load meal history');
      }
    } catch (e) {
      throw Exception('Network error: ${e.toString()}');
    }
  }

  // Get today's nutrition totals
  static Future<Map<String, dynamic>> getTodayTotals(int userId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/user/$userId/today-totals'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'totals': NutritionTotals.fromJson(data['totals']),
          'date': data['date'],
          'meals': (data['meals'] as List)
              .map((m) => MealEntry.fromJson(m))
              .toList(),
        };
      } else {
        throw Exception('Failed to load today\'s totals');
      }
    } catch (e) {
      throw Exception('Network error: ${e.toString()}');
    }
  }

  // Delete a meal entry
  static Future<void> deleteMeal(int userId, int mealId) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/user/$userId/meals/$mealId'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode != 200) {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Failed to delete meal');
      }
    } catch (e) {
      throw Exception('Network error: ${e.toString()}');
    }
  }
}

/// A list of foods plus what the server did to it (restrictions applied, why it is empty).
class FoodListResult {
  final List<FoodItem> foods;
  final String? message;
  final List<String> restrictionsApplied;
  final List<String> unsupportedRestrictions;

  FoodListResult({
    required this.foods,
    this.message,
    this.restrictionsApplied = const [],
    this.unsupportedRestrictions = const [],
  });

  factory FoodListResult.fromJson(Map<String, dynamic> json, String key) {
    return FoodListResult(
      foods: (json[key] as List).map((f) => FoodItem.fromJson(f)).toList(),
      message: json['message'],
      restrictionsApplied: List<String>.from(json['restrictions_applied'] ?? []),
      unsupportedRestrictions: List<String>.from(json['unsupported_restrictions'] ?? []),
    );
  }
}

/// The dining hall that best fits the user for a meal, or null best when none can serve them.
class HallRecommendation {
  final String? bestHall;
  final int matchingCount;
  final List<String> topFoods;
  final String? message;
  final List<String> restrictionsApplied;

  HallRecommendation({
    this.bestHall,
    this.matchingCount = 0,
    this.topFoods = const [],
    this.message,
    this.restrictionsApplied = const [],
  });

  factory HallRecommendation.fromJson(Map<String, dynamic> json) {
    final best = json['best'];
    return HallRecommendation(
      bestHall: best?['dining_hall'],
      matchingCount: best?['matching_count'] ?? 0,
      topFoods: List<String>.from(best?['top_foods'] ?? []),
      message: json['message'],
      restrictionsApplied: List<String>.from(json['restrictions_applied'] ?? []),
    );
  }
}
