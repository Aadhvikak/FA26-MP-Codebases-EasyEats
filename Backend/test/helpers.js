// Builds a throwaway data directory (nutrition DB + users + meal log) for API tests.
const fs = require('fs');
const os = require('os');
const path = require('path');
const sqlite3 = require('sqlite3');

const NEW_COLUMNS = ', ingredients TEXT, allergens TEXT, dietary_tags TEXT, tags_source TEXT';

function run(db, sql, params = []) {
    return new Promise((resolve, reject) => db.run(sql, params, (err) => (err ? reject(err) : resolve())));
}

// foods: [{hall, meal, name, tags, calories, protein, fat, carbs, fiber, sugars, sodium, category}]
// legacy: create the table the way it was before dietary labels existed
async function createDataDir({ foods, users, legacy = false }) {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'easyeats-test-'));
    const db = new sqlite3.Database(path.join(dir, 'nutrition_data.db'));

    await run(db, `CREATE TABLE nutrition_data (
        id INTEGER PRIMARY KEY AUTOINCREMENT, dining_hall TEXT, service TEXT, date TEXT,
        meal_type TEXT, category TEXT, name TEXT, serving_size TEXT, calories REAL DEFAULT 0,
        total_fat REAL DEFAULT 0, sodium REAL DEFAULT 0, total_carbohydrate REAL DEFAULT 0,
        dietary_fiber REAL DEFAULT 0, sugars REAL DEFAULT 0, protein REAL DEFAULT 0${legacy ? '' : NEW_COLUMNS})`);

    for (const f of foods) {
        const cols = ['dining_hall', 'service', 'date', 'meal_type', 'category', 'name', 'serving_size',
            'calories', 'total_fat', 'sodium', 'total_carbohydrate', 'dietary_fiber', 'sugars', 'protein'];
        const vals = [f.hall, 'Main', f.date || '2026-10-28', f.meal || 'Lunch', f.category || 'Entrees', f.name,
            f.serving || '1 serving', f.calories, f.fat || 0, f.sodium || 0, f.carbs || 0, f.fiber || 0,
            f.sugars || 0, f.protein || 0];
        if (!legacy) {
            cols.push('dietary_tags');
            vals.push(f.tags === undefined ? null : f.tags);
        }
        await run(db, `INSERT INTO nutrition_data (${cols.join(',')}) VALUES (${cols.map(() => '?').join(',')})`, vals);
    }
    await new Promise((resolve) => db.close(resolve));

    fs.writeFileSync(path.join(dir, 'users.json'), JSON.stringify({
        users: users.map((u) => ({ email: `${u.id}@test.dev`, password_hash: 'x:y', favorites: [], ...u })),
    }));
    fs.writeFileSync(path.join(dir, 'meal_tracking.json'), JSON.stringify({ meals: [] }));
    return dir;
}

// Starts the real Express app on an ephemeral port against the given data dir.
async function startServer(dataDir) {
    process.env.EASYEATS_DATA_DIR = dataDir;
    const app = require('../server');
    const server = await new Promise((resolve) => {
        const s = app.listen(0, () => resolve(s));
    });
    const base = `http://127.0.0.1:${server.address().port}`;
    return {
        base,
        get: async (p) => {
            const res = await fetch(base + p);
            return { status: res.status, body: await res.json() };
        },
        post: async (p, body) => {
            const res = await fetch(base + p, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(body),
            });
            return { status: res.status, body: await res.json() };
        },
        close: () => new Promise((resolve) => server.close(resolve)),
    };
}

module.exports = { createDataDir, startServer };
