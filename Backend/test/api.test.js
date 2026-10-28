// End-to-end tests: the real Express app against a throwaway data directory.
const test = require('node:test');
const assert = require('node:assert/strict');
const { createDataDir, startServer } = require('./helpers');

const VEGAN = 'dairy-free,egg-free,vegan,vegetarian';

const foods = [
    { hall: 'Alpha Hall', name: 'Vegan Lentil Bowl', tags: `${VEGAN},gluten-free,nut-free`, calories: 350, protein: 20, fat: 5, carbs: 50, fiber: 12 },
    { hall: 'Alpha Hall', name: 'Fried Tofu', tags: VEGAN, calories: 300, protein: 25, fat: 14, carbs: 10, fiber: 3 },
    { hall: 'Alpha Hall', name: 'Grilled Chicken', tags: 'gluten-free,nut-free', calories: 250, protein: 40, fat: 6 },
    { hall: 'Alpha Hall', name: 'Mac and Cheese', tags: 'vegetarian,nut-free', calories: 500, protein: 15, fat: 25, carbs: 45 },
    { hall: 'Alpha Hall', name: 'Mystery Stew', calories: 300, protein: 30, fat: 8 },
    // Same dish on two days, only one version vegan: must not count as vegan
    { hall: 'Alpha Hall', name: 'Veggie Wrap', date: '2026-10-28', tags: 'vegan,vegetarian', calories: 280, protein: 12, fat: 8 },
    { hall: 'Alpha Hall', name: 'Veggie Wrap', date: '2026-10-29', tags: 'vegetarian', calories: 280, protein: 12, fat: 8 },
    { hall: 'Beta Hall', name: 'Beef Burger', calories: 600, protein: 30, fat: 35 },
    { hall: 'Beta Hall', name: 'Halal Chicken', tags: 'halal', calories: 260, protein: 38, fat: 7 },
];

const users = [
    { id: 1, goal: 'Becoming fit', calories: 2000, dietary_restrictions: ['Vegan'] },
    { id: 2, goal: 'Becoming fit', calories: 2000, dietary_restrictions: ['Vegan', 'Nut Allergy'] },
    { id: 3, goal: 'Gaining weight', calories: 3000, dietary_restrictions: [] },
    { id: 4, goal: 'Losing weight', calories: 1800, dietary_restrictions: ['Kosher'] },
    { id: 5, goal: 'Becoming fit', calories: 2000, dietary_restrictions: ['Paleo'] },
];

let api;
test.before(async () => {
    api = await startServer(await createDataDir({ foods, users }));
});
test.after(() => api.close());

const names = (list) => list.map((f) => f.name);

test('vegan user is only recommended vegan foods', async () => {
    const { status, body } = await api.get('/api/recommendations/1?dining_hall=Alpha&meal_type=Lunch');
    assert.equal(status, 200);
    assert.deepEqual(names(body.recommendations).sort(), ['Fried Tofu', 'Vegan Lentil Bowl']);
    assert.deepEqual(body.restrictions_applied, ['Vegan']);
    assert.ok(!body.message);
});

test('every restriction must hold: vegan + nut allergy drops the tofu with no nut-free label', async () => {
    const { body } = await api.get('/api/recommendations/2?dining_hall=Alpha&meal_type=Lunch');
    assert.deepEqual(names(body.recommendations), ['Vegan Lentil Bowl']);
});

test('remaining recommendations are still ranked for the goal', async () => {
    const { body } = await api.get('/api/recommendations/1?dining_hall=Alpha&meal_type=Lunch');
    // For a fitness goal the lentil bowl's low fat and 12g of fiber outweigh the tofu's extra protein
    assert.deepEqual(names(body.recommendations), ['Vegan Lentil Bowl', 'Fried Tofu']);
});

test('user without restrictions still gets everything ranked, including unlabeled foods', async () => {
    const { body } = await api.get('/api/recommendations/3?dining_hall=Alpha&meal_type=Lunch');
    assert.equal(body.count, 6);
    assert.ok(names(body.recommendations).includes('Mystery Stew'));
    assert.equal(body.recommendations[0].name, 'Grilled Chicken');
});

test('when nothing meets the restrictions the API says so instead of recommending unsafe food', async () => {
    const { status, body } = await api.get('/api/recommendations/4?dining_hall=Alpha&meal_type=Lunch');
    assert.equal(status, 200);
    assert.deepEqual(body.recommendations, []);
    assert.equal(body.count, 0);
    assert.match(body.message, /No foods here meet your dietary restrictions \(Kosher\)/);
});

test('a restriction we cannot check is reported and does not hide food', async () => {
    const { body } = await api.get('/api/recommendations/5?dining_hall=Alpha&meal_type=Lunch');
    assert.deepEqual(body.unsupported_restrictions, ['Paleo']);
    assert.equal(body.count, 6);
});

test('a dish that is vegan on only some days is not recommended to vegans', async () => {
    const { body } = await api.get('/api/recommendations/1?dining_hall=Alpha&meal_type=Lunch');
    assert.ok(!names(body.recommendations).includes('Veggie Wrap'));
});

test('unknown user is a 404 and missing dining_hall is a 400', async () => {
    assert.equal((await api.get('/api/recommendations/99?dining_hall=Alpha')).status, 404);
    assert.equal((await api.get('/api/recommendations/1')).status, 400);
});

test('foods endpoint exposes dietary tags and can apply the user restrictions', async () => {
    const all = await api.get('/api/dining-halls/Alpha/foods?meal_type=Lunch');
    assert.equal(all.body.count, 6);
    assert.equal(all.body.foods.find((f) => f.name === 'Grilled Chicken').dietary_tags, 'gluten-free,nut-free');

    const filtered = await api.get('/api/dining-halls/Alpha/foods?meal_type=Lunch&user_id=1&apply_restrictions=true');
    assert.deepEqual(names(filtered.body.foods).sort(), ['Fried Tofu', 'Vegan Lentil Bowl']);
    assert.ok(filtered.body.excluded_count >= 4);

    const none = await api.get('/api/dining-halls/Alpha/foods?meal_type=Lunch&user_id=4&apply_restrictions=true');
    assert.equal(none.body.count, 0);
    assert.match(none.body.message, /Kosher/);

    assert.equal((await api.get('/api/dining-halls/Alpha/foods?apply_restrictions=true')).status, 400);
});

test('best dining hall matches restrictions and goal', async () => {
    const vegan = await api.get('/api/recommendations/1/dining-halls?meal_type=Lunch');
    assert.equal(vegan.body.best.dining_hall, 'Alpha Hall');
    assert.equal(vegan.body.best.matching_count, 2);
    const beta = vegan.body.dining_halls.find((h) => h.dining_hall === 'Beta Hall');
    assert.equal(beta.matching_count, 0);

    const halal = await api.get('/api/recommendations/3/dining-halls?meal_type=Lunch');
    assert.equal(halal.body.dining_halls.length, 2);
});

test('no hall is recommended when none can serve the user safely', async () => {
    const { body } = await api.get('/api/recommendations/4/dining-halls?meal_type=Lunch');
    assert.equal(body.best, null);
    assert.match(body.message, /Kosher/);
});

test('logging servings scales the meal totals', async () => {
    const consumed_at = new Date(Date.now()).toISOString().slice(0, 10) + 'T12:00:00';
    const res = await api.post('/api/user/3/meals', {
        meal_type: 'Lunch',
        consumed_at,
        foods: [
            { name: 'Rice', calories: 200, protein: 4, total_fat: 1, total_carbohydrate: 44, dietary_fiber: 1, quantity: 2 },
            { name: 'Chicken', calories: 250, protein: 40, total_fat: 6, quantity: 1.5 },
            { name: 'Apple', calories: 80, protein: 0, total_fat: 0, total_carbohydrate: 21, dietary_fiber: 4 },
        ],
    });
    assert.equal(res.status, 201);
    assert.equal(res.body.meal.totals.calories, 855);   // 400 + 375 + 80
    assert.equal(res.body.meal.totals.protein, 68);     // 8 + 60
    assert.equal(res.body.meal.totals.carbs, 109);      // 88 + 21
    assert.equal(res.body.meal.foods[0].quantity, 2);

    const today = await api.get('/api/user/3/today-totals');
    assert.equal(today.body.totals.calories, 855);
});

test('invalid servings are rejected', async () => {
    for (const quantity of [0, -2, 'a lot', 1000]) {
        const res = await api.post('/api/user/3/meals', {
            foods: [{ name: 'Rice', calories: 200, quantity }],
        });
        assert.equal(res.status, 400, `quantity ${quantity}`);
        assert.match(res.body.error, /quantity/);
    }
});
