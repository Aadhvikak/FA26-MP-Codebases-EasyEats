import 'package:flutter/material.dart';
import '../pages/dining_hall_detail_page.dart';
import '../services/nutrition_service.dart';
import '../services/user_service.dart';

/// The meal the user is most likely about to eat, based on the time of day.
String upcomingMealType(DateTime now) {
  if (now.hour < 10) return 'Breakfast';
  if (now.hour < 15) return 'Lunch';
  if (now.hour < 20) return 'Dinner';
  return 'Breakfast'; // dining halls are closed; the next meal is tomorrow's breakfast
}

/// Recommends the dining hall that best fits the user's dietary restrictions and
/// fitness goal for their upcoming meal.
class BestHallBanner extends StatefulWidget {
  /// Override for tests; defaults to the current time.
  final DateTime? now;

  const BestHallBanner({super.key, this.now});

  @override
  State<BestHallBanner> createState() => _BestHallBannerState();
}

class _BestHallBannerState extends State<BestHallBanner> {
  late final String _mealType = upcomingMealType(widget.now ?? DateTime.now());
  HallRecommendation? _recommendation;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = UserService.getCurrentUserId();
    if (userId == null) {
      setState(() => _loading = false);
      return;
    }

    try {
      final result = await NutritionService.getBestDiningHall(userId, _mealType);
      if (!mounted) return;
      setState(() {
        _recommendation = result;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(),
      );
    }

    final rec = _recommendation;
    if (rec == null) return const SizedBox.shrink();

    final hall = rec.bestHall;
    if (hall == null) {
      // Nothing is safe for this user right now: say so rather than suggest a hall
      if (rec.message == null) return const SizedBox.shrink();
      return _card(
        color: Colors.orange,
        icon: Icons.no_food_outlined,
        title: 'No dining hall matches for $_mealType',
        body: rec.message!,
      );
    }

    final details = [
      if (rec.restrictionsApplied.isNotEmpty) 'Matches ${rec.restrictionsApplied.join(', ')}',
      '${rec.matchingCount} matching foods',
      if (rec.topFoods.isNotEmpty) 'Try: ${rec.topFoods.join(', ')}',
    ].join(' • ');

    return _card(
      color: Colors.green,
      icon: Icons.restaurant,
      title: 'Best for your next meal ($_mealType): $hall',
      body: details,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => DiningHallDetailPage(diningHallName: hall),
        ),
      ),
    );
  }

  Widget _card({
    required MaterialColor color,
    required IconData icon,
    required String title,
    required String body,
    VoidCallback? onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: color.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.shade200),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(icon, color: color.shade700),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      key: const Key('best_hall_title'),
                      style: TextStyle(fontWeight: FontWeight.bold, color: color.shade900),
                    ),
                    const SizedBox(height: 4),
                    Text(body, style: TextStyle(fontSize: 12, color: color.shade900)),
                  ],
                ),
              ),
              if (onTap != null) Icon(Icons.chevron_right, color: color.shade700),
            ],
          ),
        ),
      ),
    );
  }
}
