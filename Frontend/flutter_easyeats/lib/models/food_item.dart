class FoodItem {
  final String name;
  final String? category;
  final String? servingSize;
  final double calories;
  final double protein;
  final double totalFat;
  final double totalCarbohydrate;
  final double? dietaryFiber;
  final double? sugars;
  final double? sodium;

  /// Dietary labels such as 'vegan' or 'gluten-free'. Empty means not labeled.
  final List<String> dietaryTags;

  /// Servings eaten. Nutrient fields above are always per one serving.
  final double quantity;

  FoodItem({
    required this.name,
    this.category,
    this.servingSize,
    required this.calories,
    required this.protein,
    required this.totalFat,
    required this.totalCarbohydrate,
    this.dietaryFiber,
    this.sugars,
    this.sodium,
    this.dietaryTags = const [],
    this.quantity = 1,
  });

  factory FoodItem.fromJson(Map<String, dynamic> json) {
    final tags = json['dietary_tags'];
    return FoodItem(
      name: json['name'] ?? '',
      category: json['category'],
      servingSize: json['serving_size'],
      calories: (json['calories'] ?? 0).toDouble(),
      protein: (json['protein'] ?? 0).toDouble(),
      totalFat: (json['total_fat'] ?? 0).toDouble(),
      totalCarbohydrate: (json['total_carbohydrate'] ?? 0).toDouble(),
      dietaryFiber: json['dietary_fiber'] != null ? (json['dietary_fiber']).toDouble() : null,
      sugars: json['sugars'] != null ? (json['sugars']).toDouble() : null,
      sodium: json['sodium'] != null ? (json['sodium']).toDouble() : null,
      dietaryTags: tags is String
          ? tags.split(',').where((t) => t.trim().isNotEmpty).toList()
          : tags is List
              ? List<String>.from(tags)
              : const [],
      quantity: (json['quantity'] ?? 1).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'category': category,
      'serving_size': servingSize,
      'calories': calories,
      'protein': protein,
      'total_fat': totalFat,
      'total_carbohydrate': totalCarbohydrate,
      'dietary_fiber': dietaryFiber,
      'sugars': sugars,
      'sodium': sodium,
      'quantity': quantity,
    };
  }

  FoodItem withQuantity(double newQuantity) {
    return FoodItem(
      name: name,
      category: category,
      servingSize: servingSize,
      calories: calories,
      protein: protein,
      totalFat: totalFat,
      totalCarbohydrate: totalCarbohydrate,
      dietaryFiber: dietaryFiber,
      sugars: sugars,
      sodium: sodium,
      dietaryTags: dietaryTags,
      quantity: newQuantity,
    );
  }

  // Amounts for everything eaten (per-serving value times servings)
  double get caloriesEaten => calories * quantity;
  double get proteinEaten => protein * quantity;
}
