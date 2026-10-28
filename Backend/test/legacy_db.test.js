// A database created before dietary labels existed must keep working, with every food unlabeled.
const test = require('node:test');
const assert = require('node:assert/strict');
const { createDataDir, startServer } = require('./helpers');

let api;
test.before(async () => {
    api = await startServer(await createDataDir({
        legacy: true,
        foods: [
            { hall: 'Alpha Hall', name: 'Rice', calories: 200, protein: 4 },
            { hall: 'Alpha Hall', name: 'Chicken', calories: 250, protein: 40 },
        ],
        users: [
            { id: 1, goal: 'Becoming fit', calories: 2000, dietary_restrictions: [] },
            { id: 2, goal: 'Becoming fit', calories: 2000, dietary_restrictions: ['Gluten-Free'] },
        ],
    }));
});
test.after(() => api.close());

test('unrestricted users still get recommendations from a pre-label database', async () => {
    const { status, body } = await api.get('/api/recommendations/1?dining_hall=Alpha');
    assert.equal(status, 200);
    assert.equal(body.count, 2);
});

test('restricted users get nothing, with an explanation, because no food is labeled', async () => {
    const { status, body } = await api.get('/api/recommendations/2?dining_hall=Alpha');
    assert.equal(status, 200);
    assert.equal(body.count, 0);
    assert.match(body.message, /Gluten-Free/);
});
