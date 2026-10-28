const test = require('node:test');
const assert = require('node:assert/strict');
const recs = require('../recommendations');
const { computeTotals, isValidQuantity } = require('../mealTotals');

const food = (name, o = {}) => ({
    name, calories: 300, protein: 10, total_fat: 5, total_carbohydrate: 30,
    dietary_fiber: 2, sugars: 3, sodium: 0.1, dietary_tags: null, ...o,
});

test('restricted foods are excluded and labeled ones kept', () => {
    const foods = [
        food('Vegan Bowl', { dietary_tags: 'vegan,vegetarian' }),
        food('Cheese Pizza', { dietary_tags: 'vegetarian' }),
        food('Chicken', { dietary_tags: 'gluten-free' }),
    ];
    const { foods: kept, applied, excluded } = recs.applyRestrictions(foods, ['Vegan']);
    assert.deepEqual(kept.map((f) => f.name), ['Vegan Bowl']);
    assert.deepEqual(applied, ['Vegan']);
    assert.equal(excluded, 2);
});

test('unlabeled foods are never assumed safe', () => {
    const { foods } = recs.applyRestrictions([food('Mystery Stew')], ['Nut Allergy']);
    assert.equal(foods.length, 0);
});

test('every restriction must be met, not just one', () => {
    const foods = [
        food('Vegan No Nuts', { dietary_tags: 'vegan,vegetarian,nut-free' }),
        food('Vegan With Nuts', { dietary_tags: 'vegan,vegetarian' }),
    ];
    const { foods: kept } = recs.applyRestrictions(foods, ['Vegan', 'Nut Allergy']);
    assert.deepEqual(kept.map((f) => f.name), ['Vegan No Nuts']);
});

test('no restrictions keeps everything', () => {
    const foods = [food('A'), food('B')];
    assert.equal(recs.applyRestrictions(foods, []).foods.length, 2);
    assert.equal(recs.applyRestrictions(foods, undefined).foods.length, 2);
});

test('nutrient restrictions use the numbers', () => {
    const foods = [
        food('Salty', { sodium: 0.9 }),
        food('Mild', { sodium: 0.05 }),
        food('Sweet', { sugars: 30 }),
        food('Carby', { total_carbohydrate: 60, dietary_fiber: 2 }),
        food('Net low carb', { total_carbohydrate: 15, dietary_fiber: 8 }),
    ];
    assert.deepEqual(recs.applyRestrictions(foods, ['Low Sodium']).foods.map((f) => f.name),
        ['Mild', 'Sweet', 'Carby', 'Net low carb']);
    assert.ok(!recs.applyRestrictions(foods, ['Low Sugar']).foods.some((f) => f.name === 'Sweet'));
    // The others default to 28 g net carbs; only the high-fiber item is under 10 g
    assert.deepEqual(recs.applyRestrictions(foods, ['Keto']).foods.map((f) => f.name), ['Net low carb']);
});

test('restrictions that cannot be checked are reported, not silently dropped', () => {
    const { applied, unsupported, foods } = recs.applyRestrictions([food('A')], ['Paleo']);
    assert.deepEqual(unsupported, ['Paleo']);
    assert.deepEqual(applied, []);
    assert.equal(foods.length, 1);
});

test('same-named dishes keep only the tags every version has', () => {
    const merged = recs.mergeByName([
        food('Veggie Wrap', { dietary_tags: 'vegan,vegetarian,nut-free' }),
        food('Veggie Wrap', { dietary_tags: 'vegetarian,nut-free' }),
        food('Rice', { dietary_tags: 'gluten-free' }),
    ]);
    assert.equal(merged.length, 2);
    assert.equal(merged.find((f) => f.name === 'Veggie Wrap').dietary_tags, 'nut-free,vegetarian');
    assert.equal(recs.applyRestrictions(merged, ['Vegan']).foods.length, 0);
});

test('a dish unlabeled in any version is unlabeled overall', () => {
    const merged = recs.mergeByName([
        food('Soup', { dietary_tags: 'vegan' }),
        food('Soup', { dietary_tags: null }),
    ]);
    assert.equal(merged[0].dietary_tags, null);
});

test('goal changes the ranking', () => {
    const lean = food('Chicken Salad', { calories: 150, protein: 20, total_fat: 3, dietary_fiber: 2 });
    const dense = food('Loaded Calzone', { calories: 700, protein: 35, total_fat: 30, dietary_fiber: 2 });

    assert.equal(recs.rankFoods([dense, lean], 'Losing weight', 667)[0].name, 'Chicken Salad');
    assert.equal(recs.rankFoods([lean, dense], 'Gaining weight', 667)[0].name, 'Loaded Calzone');
});

test('remaining recommendations are ranked for the goal after filtering', () => {
    const foods = [
        food('Fatty Vegan Curry', { calories: 600, protein: 8, total_fat: 40, dietary_fiber: 3, dietary_tags: 'vegan' }),
        food('Vegan Tofu Scramble', { calories: 250, protein: 22, total_fat: 10, dietary_fiber: 4, dietary_tags: 'vegan' }),
        food('Lean Chicken', { calories: 200, protein: 40, total_fat: 4, dietary_tags: 'gluten-free' }),
    ];
    const { foods: safe } = recs.applyRestrictions(foods, ['Vegan']);
    const ranked = recs.rankFoods(safe, 'Becoming fit', 667).map((f) => f.name);
    assert.deepEqual(ranked, ['Vegan Tofu Scramble', 'Fatty Vegan Curry']);
});

test('zero-calorie foods are never ranked', () => {
    assert.equal(recs.rankFoods([food('Water', { calories: 0 })], 'Becoming fit', 667).length, 0);
});

test('hall ranking prefers halls that can build a full meal from matching foods', () => {
    const vegan = (n) => food(n, { dietary_tags: 'vegan' });
    const rich = [vegan('a'), vegan('b'), vegan('c'), vegan('d')];
    const thin = [vegan('x')];
    const none = [food('Burger')];

    const summaries = ['Thin', 'None', 'Rich'].map((name, i) => ({
        dining_hall: name,
        ...recs.summarizeHall([thin, none, rich][i], 'Becoming fit', 667, ['Vegan']),
    }));
    const ranked = recs.rankHalls(summaries).map((s) => s.dining_hall);
    assert.deepEqual(ranked, ['Rich', 'Thin', 'None']);
    assert.equal(summaries[1].matching_count, 0);
});

test('empty message names the restrictions', () => {
    const msg = recs.emptyMessage(['Vegan', 'Nut Allergy'], 'Lunch');
    assert.match(msg, /Vegan, Nut Allergy/);
    assert.match(msg, /Lunch/);
});

test('meal totals scale by quantity and default to one serving', () => {
    const totals = computeTotals([
        { name: 'A', calories: 100, protein: 10, total_fat: 1, total_carbohydrate: 5, dietary_fiber: 1, quantity: 2 },
        { name: 'B', calories: 50, protein: 5, total_fat: 2, total_carbohydrate: 3, dietary_fiber: 0 },
        { name: 'C', calories: 200, protein: 0, quantity: 1.5 },
    ]);
    assert.equal(totals.calories, 550);
    assert.equal(totals.protein, 25);
    assert.equal(totals.fat, 4);
    assert.equal(totals.carbs, 13);
});

test('quantity validation rejects nonsense', () => {
    assert.ok(isValidQuantity({}));
    assert.ok(isValidQuantity({ quantity: 0.5 }));
    for (const quantity of [0, -1, 'two', NaN, Infinity, 51]) {
        assert.ok(!isValidQuantity({ quantity }), `quantity ${quantity} should be invalid`);
    }
});
