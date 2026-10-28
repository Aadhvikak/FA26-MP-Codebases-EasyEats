import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:easyeats/models/food_item.dart';
import 'package:easyeats/widgets/quantity_dialog.dart';

final _food = FoodItem(
  name: 'Grilled Chicken',
  servingSize: 'Piece (103g)',
  calories: 200,
  protein: 30,
  totalFat: 5,
  totalCarbohydrate: 0,
);

// Opens the dialog from a button and reports what it returned.
Future<_Harness> _open(
  WidgetTester tester, {
  double initial = 1,
  bool allowRemove = false,
}) async {
  final harness = _Harness();
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: ElevatedButton(
          onPressed: () async {
            harness.done = false;
            harness.result = await showQuantityDialog(
              context,
              _food,
              initial: initial,
              allowRemove: allowRemove,
            );
            harness.done = true;
          },
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return harness;
}

class _Harness {
  double? result;
  bool done = false;
}

String _value(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('quantity_value'))).data!;

String _preview(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('quantity_preview'))).data!;

void main() {
  testWidgets('asks how much, defaulting to one serving, and shows the serving size', (tester) async {
    await _open(tester);

    expect(find.text('How much are you having?'), findsOneWidget);
    expect(find.text('1 serving = Piece (103g)'), findsOneWidget);
    expect(_value(tester), '1 serving');
    expect(_preview(tester), '200 cal • 30g protein');
  });

  testWidgets('plus and minus change the amount in half servings and update the nutrition preview', (tester) async {
    await _open(tester);

    await tester.tap(find.byKey(const Key('quantity_increase')));
    await tester.pump();
    expect(_value(tester), '1.5 servings');
    expect(_preview(tester), '300 cal • 45g protein');

    await tester.tap(find.byKey(const Key('quantity_increase')));
    await tester.pump();
    expect(_value(tester), '2 servings');

    await tester.tap(find.byKey(const Key('quantity_decrease')));
    await tester.tap(find.byKey(const Key('quantity_decrease')));
    await tester.pump();
    expect(_value(tester), '1 serving');
  });

  testWidgets('quick picks set the amount', (tester) async {
    await _open(tester);

    await tester.tap(find.widgetWithText(ChoiceChip, '3'));
    await tester.pump();
    expect(_value(tester), '3 servings');
    expect(_preview(tester), '600 cal • 90g protein');
  });

  testWidgets('cannot go below half a serving', (tester) async {
    await _open(tester, initial: 0.5);

    expect(_value(tester), '0.5 servings');
    final minus = tester.widget<IconButton>(find.byKey(const Key('quantity_decrease')));
    expect(minus.onPressed, isNull);
  });

  testWidgets('Add returns the chosen amount', (tester) async {
    final harness = await _open(tester);

    await tester.tap(find.byKey(const Key('quantity_increase')));
    await tester.tap(find.byKey(const Key('quantity_increase')));
    await tester.pump();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(harness.done, isTrue);
    expect(harness.result, 2);
  });

  testWidgets('Cancel returns nothing, so the food is not selected', (tester) async {
    final harness = await _open(tester);

    await tester.tap(find.byKey(const Key('quantity_increase')));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(harness.done, isTrue);
    expect(harness.result, isNull);
  });

  testWidgets('editing an already selected food starts from its amount and can remove it', (tester) async {
    final harness = await _open(tester, initial: 2, allowRemove: true);

    expect(_value(tester), '2 servings');
    expect(find.text('Update'), findsOneWidget);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(harness.result, 0);
  });

  testWidgets('Remove is only offered when editing', (tester) async {
    await _open(tester);
    expect(find.text('Remove'), findsNothing);
  });

  test('formatServings drops a trailing .0', () {
    expect(formatServings(1), '1');
    expect(formatServings(1.5), '1.5');
    expect(formatServings(0.5), '0.5');
  });
}
