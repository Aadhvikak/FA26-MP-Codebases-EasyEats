import 'package:flutter/material.dart';
import '../models/food_item.dart';

const double kQuantityStep = 0.5;
const double kMinQuantity = 0.5;
const double kMaxQuantity = 20;

/// "1", "1.5", "2" - servings without a trailing ".0".
String formatServings(double quantity) {
  return quantity == quantity.roundToDouble()
      ? quantity.toInt().toString()
      : quantity.toString();
}

/// Asks how many servings of [food] the user is having.
///
/// Returns the chosen number of servings, 0 if the user chose to remove the
/// food (only offered when [allowRemove] is true), or null if they cancelled.
Future<double?> showQuantityDialog(
  BuildContext context,
  FoodItem food, {
  double initial = 1,
  bool allowRemove = false,
}) {
  return showDialog<double>(
    context: context,
    builder: (context) => QuantityDialog(
      food: food,
      initial: initial,
      allowRemove: allowRemove,
    ),
  );
}

class QuantityDialog extends StatefulWidget {
  final FoodItem food;
  final double initial;
  final bool allowRemove;

  const QuantityDialog({
    super.key,
    required this.food,
    this.initial = 1,
    this.allowRemove = false,
  });

  @override
  State<QuantityDialog> createState() => _QuantityDialogState();
}

class _QuantityDialogState extends State<QuantityDialog> {
  late double _quantity;

  static const List<double> _quickPicks = [0.5, 1, 1.5, 2, 3];

  @override
  void initState() {
    super.initState();
    _quantity = widget.initial.clamp(kMinQuantity, kMaxQuantity).toDouble();
  }

  void _change(double delta) {
    setState(() {
      _quantity = (_quantity + delta).clamp(kMinQuantity, kMaxQuantity).toDouble();
    });
  }

  @override
  Widget build(BuildContext context) {
    final food = widget.food;
    final serving = food.servingSize;

    return AlertDialog(
      title: Text(food.name),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('How much are you having?'),
          if (serving != null && serving.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '1 serving = $serving',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                key: const Key('quantity_decrease'),
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: _quantity > kMinQuantity ? () => _change(-kQuantityStep) : null,
              ),
              SizedBox(
                width: 96,
                child: Text(
                  '${formatServings(_quantity)} ${_quantity == 1 ? 'serving' : 'servings'}',
                  key: const Key('quantity_value'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                key: const Key('quantity_increase'),
                icon: const Icon(Icons.add_circle_outline),
                onPressed: _quantity < kMaxQuantity ? () => _change(kQuantityStep) : null,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            alignment: WrapAlignment.center,
            children: _quickPicks.map((q) {
              return ChoiceChip(
                label: Text(formatServings(q)),
                selected: _quantity == q,
                onSelected: (_) => setState(() => _quantity = q),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              '${(food.calories * _quantity).round()} cal • ${(food.protein * _quantity).round()}g protein',
              key: const Key('quantity_preview'),
              style: TextStyle(color: Colors.grey[700]),
            ),
          ),
        ],
      ),
      actions: [
        if (widget.allowRemove)
          TextButton(
            onPressed: () => Navigator.pop(context, 0.0),
            child: const Text('Remove'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _quantity),
          style: FilledButton.styleFrom(backgroundColor: Colors.green),
          child: Text(widget.allowRemove ? 'Update' : 'Add'),
        ),
      ],
    );
  }
}
