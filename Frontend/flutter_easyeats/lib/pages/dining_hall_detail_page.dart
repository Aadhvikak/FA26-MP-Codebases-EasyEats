import 'package:flutter/material.dart';
import '../models/food_item.dart';
import '../services/nutrition_service.dart';
import '../services/user_service.dart';
import '../widgets/quantity_dialog.dart';

class DiningHallDetailPage extends StatefulWidget {
  final String diningHallName;

  const DiningHallDetailPage({
    super.key,
    required this.diningHallName,
  });

  @override
  State<DiningHallDetailPage> createState() => _DiningHallDetailPageState();
}

class _DiningHallDetailPageState extends State<DiningHallDetailPage> {
  bool _isLoading = true;
  bool _showRecommendations = true;
  List<FoodItem> _recommendations = [];
  List<FoodItem> _allFoods = [];
  final List<FoodItem> _selectedFoods = [];
  String _selectedMealType = 'Lunch';
  int? _userId;
  int _targetCalories = 2000;
  String _userGoal = '';
  String _error = '';
  String _searchQuery = '';

  // Dietary restrictions the server applied to the recommendations (always on, for safety)
  List<String> _restrictionsApplied = [];
  List<String> _unsupportedRestrictions = [];
  String? _recommendationsMessage;
  String? _allFoodsMessage;
  bool _applyToAllFoods = true;

  final List<String> _mealTypes = ['Breakfast', 'Lunch', 'Dinner'];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final user = await UserService.getCurrentUser();
      if (user == null) {
        setState(() {
          _error = 'Not logged in';
          _isLoading = false;
        });
        return;
      }

      _userId = user['id'];
      _targetCalories = user['calories'] ?? 2000;
      _userGoal = user['goal'] ?? '';

      // Load recommendations and all foods in parallel
      await Future.wait([
        _loadRecommendations(),
        _loadAllFoods(),
      ]);

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadRecommendations() async {
    try {
      final result = await NutritionService.getRecommendations(
        _userId!,
        widget.diningHallName,
        mealType: _selectedMealType,
      );

      setState(() {
        _recommendations = result['recommendations'];
        _recommendationsMessage = result['message'];
        _restrictionsApplied = result['restrictions_applied'];
        _unsupportedRestrictions = result['unsupported_restrictions'];
        if (_recommendations.isEmpty) {
          _error = '';
        }
      });
    } catch (e) {
      setState(() {
        _recommendations = [];
        _recommendationsMessage = null;
        _error = '';
      });
    }
  }

  Future<void> _loadAllFoods() async {
    try {
      final result = await NutritionService.getFoodListResult(
        widget.diningHallName,
        mealType: _selectedMealType,
        userId: _userId,
        applyRestrictions: _applyToAllFoods,
      );

      setState(() {
        _allFoods = result.foods;
        _allFoodsMessage = result.message;
        if (_allFoods.isEmpty) {
          _error = '';
        }
      });
    } catch (e) {
      setState(() {
        _allFoods = [];
        _allFoodsMessage = null;
        _error = '';
      });
    }
  }

  int _selectedIndex(FoodItem food) {
    return _selectedFoods.indexWhere((f) => f.name == food.name);
  }

  bool _isFoodSelected(FoodItem food) => _selectedIndex(food) >= 0;

  // Ask how many servings; picking again on a selected food edits (or removes) it
  Future<void> _promptForQuantity(FoodItem food) async {
    final index = _selectedIndex(food);
    final existing = index >= 0 ? _selectedFoods[index] : null;

    final quantity = await showQuantityDialog(
      context,
      food,
      initial: existing?.quantity ?? 1,
      allowRemove: existing != null,
    );
    if (quantity == null || !mounted) return;

    setState(() {
      // The list can change while the dialog is open, so look the food up again
      final current = _selectedIndex(food);
      if (quantity == 0) {
        if (current >= 0) _selectedFoods.removeAt(current);
      } else if (current >= 0) {
        _selectedFoods[current] = food.withQuantity(quantity);
      } else {
        _selectedFoods.add(food.withQuantity(quantity));
      }
    });
  }

  void _removeFood(FoodItem food) {
    setState(() {
      _selectedFoods.removeWhere((f) => f.name == food.name);
    });
  }

  // Tags worth showing; vegan already implies vegetarian, dairy-free and egg-free
  List<String> _displayTags(FoodItem food) {
    final tags = food.dietaryTags.toSet();
    if (tags.contains('vegan')) {
      tags.removeAll(['vegetarian', 'dairy-free', 'egg-free']);
    }
    return tags.toList()..sort();
  }

  Future<void> _logMeal() async {
    if (_selectedFoods.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one food item')),
      );
      return;
    }

    try {
      await NutritionService.logMeal(
        _userId!,
        _selectedFoods,
        mealType: _selectedMealType,
        diningHall: widget.diningHallName,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Logged ${_selectedFoods.length} items to $_selectedMealType'),
            backgroundColor: Colors.green,
          ),
        );

        setState(() {
          _selectedFoods.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error logging meal: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // The server's explanation when the list is empty because of dietary restrictions
  String? get _restrictionMessage {
    if (_searchQuery.isNotEmpty) return null;
    return _showRecommendations ? _recommendationsMessage : _allFoodsMessage;
  }

  List<FoodItem> get _filteredFoods {
    final foods = _showRecommendations ? _recommendations : _allFoods;

    if (_searchQuery.isEmpty) {
      return foods;
    }

    return foods.where((food) {
      return food.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
             (food.category?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false);
    }).toList();
  }

  double get _selectedTotalCalories {
    return _selectedFoods.fold(0, (sum, food) => sum + food.caloriesEaten);
  }

  double get _selectedTotalProtein {
    return _selectedFoods.fold(0, (sum, food) => sum + food.proteinEaten);
  }

  double get _selectedServings {
    return _selectedFoods.fold(0, (sum, food) => sum + food.quantity);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.diningHallName),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Meal type selector
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey[100],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Meal Type',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Row(
                  children: _mealTypes.map((type) {
                    final isSelected = type == _selectedMealType;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(type),
                        selected: isSelected,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() {
                              _selectedMealType = type;
                            });
                            _loadData();
                          }
                        },
                        selectedColor: Colors.green,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : Colors.black,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),

          // Search bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search foods...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.grey[200],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
          ),

          // Toggle between recommendations and all foods
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: true,
                        label: Text('Recommended'),
                        icon: Icon(Icons.star, size: 16),
                      ),
                      ButtonSegment(
                        value: false,
                        label: Text('All Foods'),
                        icon: Icon(Icons.restaurant, size: 16),
                      ),
                    ],
                    selected: {_showRecommendations},
                    onSelectionChanged: (Set<bool> selection) {
                      setState(() {
                        _showRecommendations = selection.first;
                      });
                    },
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // User goal banner
          if (_userGoal.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.track_changes, color: Colors.blue.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Goal: $_userGoal • ${(_targetCalories / 3).toInt()} cal per meal',
                      style: TextStyle(fontSize: 12, color: Colors.blue.shade900),
                    ),
                  ),
                ],
              ),
            ),

          // Dietary restrictions being applied
          if (_restrictionsApplied.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.verified_user, color: Colors.green.shade700, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Matching your restrictions: ${_restrictionsApplied.join(', ')}',
                          style: TextStyle(fontSize: 12, color: Colors.green.shade900),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Also filter All Foods',
                          style: TextStyle(fontSize: 12, color: Colors.green.shade900),
                        ),
                      ),
                      Switch(
                        value: _applyToAllFoods,
                        activeThumbColor: Colors.green,
                        onChanged: (value) {
                          setState(() => _applyToAllFoods = value);
                          _loadAllFoods();
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),

          if (_unsupportedRestrictions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                "Not filtered (can't be checked from menu data): ${_unsupportedRestrictions.join(', ')}",
                style: TextStyle(fontSize: 11, color: Colors.orange.shade800),
              ),
            ),

          // Error message
          if (_error.isNotEmpty)
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Text(_error, style: TextStyle(color: Colors.red.shade700)),
            ),

          // Foods list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredFoods.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _restrictionMessage != null ? Icons.no_food_outlined : Icons.restaurant_menu_outlined,
                                size: 80,
                                color: Colors.grey[300],
                              ),
                              const SizedBox(height: 24),
                              Text(
                                _restrictionMessage ??
                                    'Oops! It seems like there are no meals being served at this dining hall currently.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[600],
                                  height: 1.5,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _searchQuery.isNotEmpty
                                    ? 'Try adjusting your search or check back later.'
                                    : _restrictionMessage != null
                                        ? 'Try a different dining hall or meal.'
                                        : 'Try selecting a different dining hall or check back later.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _filteredFoods.length,
                        itemBuilder: (context, index) {
                          final food = _filteredFoods[index];
                          final isSelected = _isFoodSelected(food);
                          final servings = isSelected
                              ? _selectedFoods[_selectedIndex(food)].quantity
                              : 0.0;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            elevation: isSelected ? 4 : 1,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: isSelected ? Colors.green : Colors.grey.shade300,
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: InkWell(
                              onTap: () => _promptForQuantity(food),
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    Checkbox(
                                      value: isSelected,
                                      onChanged: (_) => isSelected
                                          ? _removeFood(food)
                                          : _promptForQuantity(food),
                                      activeColor: Colors.green,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            food.name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                          if (food.category != null) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              food.category!,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey[600],
                                              ),
                                            ),
                                          ],
                                          const SizedBox(height: 8),
                                          Row(
                                            children: [
                                              _buildNutrientChip(
                                                '${food.calories.toInt()} cal',
                                                Colors.orange,
                                              ),
                                              const SizedBox(width: 8),
                                              _buildNutrientChip(
                                                'P: ${food.protein.toInt()}g',
                                                Colors.blue,
                                              ),
                                              const SizedBox(width: 8),
                                              _buildNutrientChip(
                                                'C: ${food.totalCarbohydrate.toInt()}g',
                                                Colors.green,
                                              ),
                                              const SizedBox(width: 8),
                                              _buildNutrientChip(
                                                'F: ${food.totalFat.toInt()}g',
                                                Colors.red,
                                              ),
                                            ],
                                          ),
                                          if (_displayTags(food).isNotEmpty) ...[
                                            const SizedBox(height: 8),
                                            Wrap(
                                              spacing: 6,
                                              runSpacing: 4,
                                              children: _displayTags(food)
                                                  .map((t) => _buildNutrientChip(t, Colors.teal))
                                                  .toList(),
                                            ),
                                          ],
                                          if (isSelected) ...[
                                            const SizedBox(height: 8),
                                            Text(
                                              '${formatServings(servings)} ${servings == 1 ? 'serving' : 'servings'}'
                                              ' • ${(food.calories * servings).round()} cal  (tap to change)',
                                              key: Key('servings_${food.name}'),
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.green.shade800,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      bottomNavigationBar: _selectedFoods.isNotEmpty
          ? Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.shade300,
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_selectedFoods.length} items • ${formatServings(_selectedServings)} servings',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${_selectedTotalCalories.toInt()} cal • ${_selectedTotalProtein.toInt()}g protein',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                        ElevatedButton.icon(
                          onPressed: _logMeal,
                          icon: const Icon(Icons.add),
                          label: const Text('Log Meal'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildNutrientChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}
