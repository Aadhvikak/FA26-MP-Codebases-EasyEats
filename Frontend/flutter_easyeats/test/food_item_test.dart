import 'package:flutter_test/flutter_test.dart';
import 'package:easyeats/models/food_item.dart';
import 'package:easyeats/widgets/best_hall_banner.dart';

void main() {
  final json = {
    'name': 'Grilled Chicken',
    'serving_size': 'Piece (103g)',
    'calories': 250,
    'protein': 40,
    'total_fat': 6,
    'total_carbohydrate': 0,
    'dietary_tags': 'gluten-free,halal',
  };

  group('FoodItem', () {
    test('dietary tags parse from the server\'s comma separated string', () {
      expect(FoodItem.fromJson(json).dietaryTags, ['gluten-free', 'halal']);
    });

    test('missing or null tags mean unlabeled, not safe', () {
      expect(FoodItem.fromJson({...json, 'dietary_tags': null}).dietaryTags, isEmpty);
      expect(FoodItem.fromJson({...json}..remove('dietary_tags')).dietaryTags, isEmpty);
      expect(FoodItem.fromJson({...json, 'dietary_tags': ''}).dietaryTags, isEmpty);
    });

    test('defaults to one serving, as meals logged before servings existed', () {
      expect(FoodItem.fromJson(json).quantity, 1);
    });

    test('withQuantity scales what was eaten but not the per-serving values', () {
      final food = FoodItem.fromJson(json).withQuantity(2.5);
      expect(food.quantity, 2.5);
      expect(food.calories, 250);
      expect(food.caloriesEaten, 625);
      expect(food.proteinEaten, 100);
      expect(food.dietaryTags, ['gluten-free', 'halal']);
    });

    test('quantity is sent to the server when logging', () {
      final sent = FoodItem.fromJson(json).withQuantity(1.5).toJson();
      expect(sent['quantity'], 1.5);
      expect(sent['calories'], 250);
    });

    test('quantity round-trips through JSON', () {
      final food = FoodItem.fromJson(FoodItem.fromJson(json).withQuantity(3).toJson());
      expect(food.quantity, 3);
    });
  });

  group('upcomingMealType', () {
    String at(int hour) => upcomingMealType(DateTime(2026, 10, 28, hour));

    test('picks the meal by time of day', () {
      expect(at(7), 'Breakfast');
      expect(at(12), 'Lunch');
      expect(at(17), 'Dinner');
    });

    test('after dinner, the next meal is tomorrow\'s breakfast', () {
      expect(at(21), 'Breakfast');
    });
  });
}
