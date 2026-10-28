import 'dart:convert';

import 'package:easyeats/pages/dining_hall_detail_page.dart';
import 'package:easyeats/services/user_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _food(String name, String tags, {double calories = 250}) => {
      'name': name,
      'category': 'Entrees',
      'serving_size': '1 bowl',
      'calories': calories,
      'protein': 20,
      'total_fat': 5,
      'total_carbohydrate': 30,
      'dietary_tags': tags,
    };

/// Runs [body] with every http call answered by [handler]; records the requests.
Future<void> _withServer(
  WidgetTester tester,
  Map<String, dynamic> Function(http.Request request) handler,
  List<http.Request> requests,
  Future<void> Function() body,
) async {
  SharedPreferences.setMockInitialValues({});
  await UserService.setCurrentUser(1, {'calories': 2000, 'goal': 'Becoming fit'});

  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await http.runWithClient(body, () => MockClient((request) async {
        requests.add(request);
        final status = request.method == 'POST' ? 201 : 200;
        return http.Response(json.encode(handler(request)), status,
            headers: {'content-type': 'application/json'});
      }));
}

Future<void> _openPage(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(
    home: DiningHallDetailPage(diningHallName: 'Ike'),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the restrictions being applied and each food\'s dietary labels', (tester) async {
    await _withServer(tester, (request) {
      if (request.url.path.contains('/recommendations/')) {
        return {
          'recommendations': [_food('Vegan Lentil Bowl', 'dairy-free,egg-free,vegan,vegetarian')],
          'count': 1,
          'restrictions_applied': ['Vegan'],
          'unsupported_restrictions': ['Paleo'],
        };
      }
      return {'foods': [], 'count': 0};
    }, [], () async {
      await _openPage(tester);

      expect(find.text('Vegan Lentil Bowl'), findsOneWidget);
      expect(find.text('Matching your restrictions: Vegan'), findsOneWidget);
      expect(find.textContaining('Not filtered'), findsOneWidget);
      expect(find.textContaining('Paleo'), findsOneWidget);
      // 'vegan' is shown; the labels it implies are not repeated
      expect(find.text('vegan'), findsOneWidget);
      expect(find.text('vegetarian'), findsNothing);
    });
  });

  testWidgets('explains when nothing meets the restrictions instead of recommending anything', (tester) async {
    await _withServer(tester, (request) {
      if (request.url.path.contains('/recommendations/')) {
        return {
          'recommendations': [],
          'count': 0,
          'restrictions_applied': ['Kosher'],
          'message': 'No foods here meet your dietary restrictions (Kosher) for Lunch, so we aren\'t '
              'recommending anything.',
        };
      }
      return {'foods': [], 'count': 0};
    }, [], () async {
      await _openPage(tester);

      expect(find.textContaining('No foods here meet your dietary restrictions (Kosher)'), findsOneWidget);
      expect(find.textContaining('no meals being served'), findsNothing);
    });
  });

  testWidgets('asks how much of a food, then logs that amount and the scaled totals', (tester) async {
    final requests = <http.Request>[];
    await _withServer(tester, (request) {
      if (request.method == 'POST') {
        return {
          'success': true,
          'meal': {
            'id': 1,
            'user_id': 1,
            'meal_type': 'Lunch',
            'dining_hall': 'Ike',
            'consumed_at': DateTime.now().toIso8601String(),
            'foods': [],
            'totals': {'calories': 375, 'protein': 30, 'fat': 7.5, 'carbs': 45, 'fiber': 0},
          },
        };
      }
      if (request.url.path.contains('/recommendations/')) {
        return {
          'recommendations': [_food('Vegan Lentil Bowl', 'vegan')],
          'count': 1,
          'restrictions_applied': [],
        };
      }
      return {'foods': [], 'count': 0};
    }, requests, () async {
      await _openPage(tester);

      // Picking a food asks how much instead of assuming one
      await tester.tap(find.text('Vegan Lentil Bowl'));
      await tester.pumpAndSettle();
      expect(find.text('How much are you having?'), findsOneWidget);

      await tester.tap(find.byKey(const Key('quantity_increase')));
      await tester.pump();
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('servings_Vegan Lentil Bowl')), findsOneWidget);
      expect(find.text('1.5 servings • 375 cal  (tap to change)'), findsOneWidget);
      expect(find.text('1 items • 1.5 servings'), findsOneWidget);
      expect(find.text('375 cal • 30g protein'), findsOneWidget);

      // Tapping it again edits the amount
      await tester.tap(find.text('Vegan Lentil Bowl'));
      await tester.pumpAndSettle();
      expect(find.text('Update'), findsOneWidget);
      await tester.tap(find.byKey(const Key('quantity_increase')));
      await tester.pump();
      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();
      expect(find.text('2 servings • 500 cal  (tap to change)'), findsOneWidget);

      await tester.tap(find.text('Log Meal'));
      await tester.pumpAndSettle();

      final post = requests.singleWhere((r) => r.method == 'POST');
      final sent = json.decode(post.body);
      expect(sent['foods'], hasLength(1));
      expect(sent['foods'][0]['quantity'], 2);
      expect(sent['foods'][0]['calories'], 250); // per serving; the server scales it
    });
  });

  testWidgets('cancelling the prompt does not select the food; Remove deselects it', (tester) async {
    await _withServer(tester, (request) {
      if (request.url.path.contains('/recommendations/')) {
        return {
          'recommendations': [_food('Vegan Lentil Bowl', 'vegan')],
          'count': 1,
          'restrictions_applied': [],
        };
      }
      return {'foods': [], 'count': 0};
    }, [], () async {
      await _openPage(tester);

      await tester.tap(find.text('Vegan Lentil Bowl'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Log Meal'), findsNothing);

      await tester.tap(find.text('Vegan Lentil Bowl'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(find.text('Log Meal'), findsOneWidget);

      await tester.tap(find.text('Vegan Lentil Bowl'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(find.text('Log Meal'), findsNothing);
    });
  });
}
