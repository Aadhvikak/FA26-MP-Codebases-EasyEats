const express = require('express');
const cors = require('cors');
const { spawn } = require('child_process');
const path = require('path');
const auth = require('./auth');
const sqlite3 = require('sqlite3').verbose();
const fs = require('fs');
const recs = require('./recommendations');
const { isValidQuantity, computeTotals, MAX_QUANTITY } = require('./mealTotals');

const app = express();
const PORT = process.env.PORT || 3000;

// EASYEATS_DATA_DIR lets tests run against a throwaway data directory
const DATA_DIR = process.env.EASYEATS_DATA_DIR || path.join(__dirname, 'data');

// Database connection
const dbPath = path.join(DATA_DIR, 'nutrition_data.db');
const db = new sqlite3.Database(dbPath);

// Databases created before dietary labels existed lack these columns; add them so queries work.
// Rows without labels simply have no dietary tags (unknown), which the filter treats as unsafe.
const DIETARY_COLUMNS = ['ingredients', 'allergens', 'dietary_tags', 'tags_source'];
const dietaryColumnsReady = new Promise((resolve) => {
    db.all('PRAGMA table_info(nutrition_data)', [], (err, cols) => {
        if (err || !cols || cols.length === 0) return resolve();
        const have = new Set(cols.map((c) => c.name));
        const missing = DIETARY_COLUMNS.filter((c) => !have.has(c));
        db.serialize(() => {
            missing.forEach((c) => db.run(`ALTER TABLE nutrition_data ADD COLUMN ${c} TEXT`));
            db.run('SELECT 1', [], () => resolve());
        });
    });
});

async function dbAll(sql, params = []) {
    await dietaryColumnsReady;
    return new Promise((resolve, reject) => {
        db.all(sql, params, (err, rows) => (err ? reject(err) : resolve(rows)));
    });
}

function getProfile(userId) {
    return new Promise((resolve, reject) => {
        auth.getUserProfile(userId, (err, user) => (err ? reject(err) : resolve(user)));
    });
}

const FOOD_COLUMNS = `name, category, serving_size, calories, protein, total_fat,
        total_carbohydrate, dietary_fiber, sugars, sodium, ingredients, allergens, dietary_tags`;

// Every row for a hall/meal, merged so each dish appears once (see mergeByName for tag safety)
async function loadHallFoods(hall, { mealType, date } = {}) {
    let query = `SELECT ${FOOD_COLUMNS} FROM nutrition_data WHERE dining_hall LIKE ?`;
    const params = [`%${hall}%`];
    if (mealType) {
        query += ' AND meal_type = ?';
        params.push(mealType);
    }
    if (date) {
        query += ' AND date = ?';
        params.push(date);
    }
    return recs.mergeByName(await dbAll(query, params));
}

// Middleware
app.use(cors());
app.use(express.json());

// API Endpoint
app.get('/api/meal-plan', (req, res) => {
    const { calories, dining_hall, meal_type } = req.query;

    // Validate required parameters
    if (!calories || !dining_hall) {
        return res.status(400).json({
            error: 'Missing required parameters: calories and dining_hall are required'
        });
    }

    // Path to Python script
    const scriptPath = path.join(__dirname, 'meal-planning', 'meal_planner.py');

    // Build arguments
    const args = [
        scriptPath,
        '--calories', calories,
        '--hall', dining_hall,
        '--json' // Force JSON output
    ];

    if (meal_type) {
        args.push('--meal', meal_type);
    }

    if (req.query.goal) {
        args.push('--goal', req.query.goal);
    }

    // Spawn Python process
    // Note: Using 'python3' - make sure it's in the path
    const pythonProcess = spawn('python3', args);

    let dataString = '';
    let errorString = '';

    // Collect data from stdout
    pythonProcess.stdout.on('data', (data) => {
        dataString += data.toString();
    });

    // Collect errors from stderr
    pythonProcess.stderr.on('data', (data) => {
        errorString += data.toString();
    });

    // Handle process close
    pythonProcess.on('close', (code) => {
        if (code !== 0) {
            console.error(`Python script exited with code ${code}`);
            console.error(`Error: ${errorString}`);
            return res.status(500).json({
                error: 'Failed to generate meal plan',
                details: errorString
            });
        }

        try {
            // Parse JSON output from Python script
            // The script might print other things (like warnings) to stdout if not careful
            // But our modified script should only print JSON when --json is used
            // We'll try to find the JSON object in the output if there's extra noise

            // Simple attempt: parse the whole string
            const mealPlan = JSON.parse(dataString);
            res.json(mealPlan);
        } catch (e) {
            console.error('Failed to parse JSON output:', e);
            console.error('Raw output:', dataString);

            // Fallback: try to find the last JSON object in the output
            try {
                const lines = dataString.trim().split('\n');
                const lastLine = lines[lines.length - 1];
                const mealPlan = JSON.parse(lastLine);
                res.json(mealPlan);
            } catch (e2) {
                res.status(500).json({
                    error: 'Invalid response from meal planner',
                    raw_output: dataString
                });
            }
        }
    });
});

// Authentication endpoints
app.post('/api/auth/register', (req, res) => {
    const { email, password } = req.body;

    if (!email || !password) {
        return res.status(400).json({ error: 'Email and password are required' });
    }

    // Basic email validation
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(email)) {
        return res.status(400).json({ error: 'Invalid email format' });
    }

    // Password length check
    if (password.length < 6) {
        return res.status(400).json({ error: 'Password must be at least 6 characters' });
    }

    auth.registerUser(email, password, (err, result) => {
        if (err) {
            return res.status(400).json(err);
        }
        res.status(201).json(result);
    });
});

app.post('/api/auth/login', (req, res) => {
    const { email, password } = req.body;

    if (!email || !password) {
        return res.status(400).json({ error: 'Email and password are required' });
    }

    auth.loginUser(email, password, (err, result) => {
        if (err) {
            return res.status(401).json(err);
        }
        res.json(result);
    });
});

app.put('/api/user/:userId/profile', (req, res) => {
    const userId = parseInt(req.params.userId);
    const profileData = req.body;

    auth.updateUserProfile(userId, profileData, (err, result) => {
        if (err) {
            return res.status(400).json(err);
        }
        res.json(result);
    });
});

app.get('/api/user/:userId/profile', (req, res) => {
    const userId = parseInt(req.params.userId);

    auth.getUserProfile(userId, (err, result) => {
        if (err) {
            return res.status(404).json(err);
        }
        res.json(result);
    });
});

app.post('/api/user/:userId/change-password', (req, res) => {
    const userId = parseInt(req.params.userId);
    const { oldPassword, newPassword } = req.body;

    if (!oldPassword || !newPassword) {
        return res.status(400).json({ error: 'Old and new passwords are required' });
    }

    if (newPassword.length < 6) {
        return res.status(400).json({ error: 'New password must be at least 6 characters' });
    }

    auth.changePassword(userId, oldPassword, newPassword, (err, result) => {
        if (err) {
            return res.status(400).json(err);
        }
        res.json(result);
    });
});

app.post('/api/user/:userId/favorites', (req, res) => {
    const userId = parseInt(req.params.userId);
    const { foodItem } = req.body;

    if (!foodItem) {
        return res.status(400).json({ error: 'Food item is required' });
    }

    auth.addFavorite(userId, foodItem, (err, result) => {
        if (err) {
            return res.status(400).json(err);
        }
        res.json(result);
    });
});

app.delete('/api/user/:userId/favorites/:index', (req, res) => {
    const userId = parseInt(req.params.userId);
    const index = parseInt(req.params.index);

    auth.removeFavorite(userId, index, (err, result) => {
        if (err) {
            return res.status(400).json(err);
        }
        res.json(result);
    });
});

// ============ NUTRITION DATA ENDPOINTS ============

// Get all available dining halls
app.get('/api/dining-halls', (req, res) => {
    const query = `SELECT DISTINCT dining_hall FROM nutrition_data ORDER BY dining_hall`;

    db.all(query, [], (err, rows) => {
        if (err) {
            return res.status(500).json({ error: 'Database error', details: err.message });
        }
        const halls = rows.map(row => row.dining_hall);
        res.json({ dining_halls: halls });
    });
});

// Get foods for a specific dining hall and meal type
// With user_id and apply_restrictions=true, only foods that meet that user's dietary restrictions are returned.
app.get('/api/dining-halls/:hall/foods', async (req, res) => {
    const { hall } = req.params;
    const { meal_type, date, user_id, apply_restrictions } = req.query;

    try {
        let foods = await loadHallFoods(hall, { mealType: meal_type, date });
        const body = {};

        if (apply_restrictions === 'true') {
            if (!user_id) {
                return res.status(400).json({ error: 'user_id is required to apply restrictions' });
            }
            const user = await getProfile(parseInt(user_id));
            const result = recs.applyRestrictions(foods, user.dietary_restrictions);
            foods = result.foods;
            body.restrictions_applied = result.applied;
            body.unsupported_restrictions = result.unsupported;
            body.excluded_count = result.excluded;
            if (foods.length === 0 && result.applied.length > 0) {
                body.message = recs.emptyMessage(result.applied, meal_type);
            }
        }

        foods.sort((a, b) => (a.category || '').localeCompare(b.category || '') || a.name.localeCompare(b.name));
        res.json({ foods, count: foods.length, ...body });
    } catch (err) {
        if (err && err.error === 'User not found') return res.status(404).json(err);
        res.status(500).json({ error: 'Database error', details: err.message || String(err) });
    }
});

// Get recommended foods for user based on goals
// Restrictions are applied first; what is left is ranked for the user's goal.
app.get('/api/recommendations/:userId', async (req, res) => {
    const userId = parseInt(req.params.userId);
    const { dining_hall, meal_type } = req.query;

    if (!dining_hall) {
        return res.status(400).json({ error: 'dining_hall is required' });
    }

    try {
        const user = await getProfile(userId);
        const targetCaloriesPerMeal = Math.floor((user.calories || 2000) / 3);

        const allFoods = await loadHallFoods(dining_hall, { mealType: meal_type });
        const result = recs.applyRestrictions(allFoods, user.dietary_restrictions);
        const ranked = recs.rankFoods(result.foods, user.goal, targetCaloriesPerMeal).slice(0, 20);

        const body = {
            recommendations: ranked,
            user_target_calories: targetCaloriesPerMeal,
            goal: user.goal,
            count: ranked.length,
            restrictions_applied: result.applied,
            unsupported_restrictions: result.unsupported,
            excluded_count: result.excluded,
        };
        if (ranked.length === 0 && result.applied.length > 0 && allFoods.length > 0) {
            body.message = recs.emptyMessage(result.applied, meal_type);
        }
        res.json(body);
    } catch (err) {
        if (err && err.error === 'User not found') return res.status(404).json(err);
        res.status(500).json({ error: 'Database error', details: err.message || String(err) });
    }
});

// Which dining hall best fits this user's restrictions and goal for a meal
app.get('/api/recommendations/:userId/dining-halls', async (req, res) => {
    const userId = parseInt(req.params.userId);
    const { meal_type } = req.query;

    try {
        const user = await getProfile(userId);
        const targetCaloriesPerMeal = Math.floor((user.calories || 2000) / 3);
        const halls = (await dbAll('SELECT DISTINCT dining_hall FROM nutrition_data ORDER BY dining_hall'))
            .map((r) => r.dining_hall);

        const summaries = [];
        for (const hall of halls) {
            const foods = await loadHallFoods(hall, { mealType: meal_type });
            summaries.push({
                dining_hall: hall,
                ...recs.summarizeHall(foods, user.goal, targetCaloriesPerMeal, user.dietary_restrictions),
            });
        }

        const ranked = recs.rankHalls(summaries);
        const best = ranked.length > 0 && ranked[0].matching_count > 0 ? ranked[0] : null;
        const restrictions = recs.applyRestrictions([], user.dietary_restrictions);

        const body = {
            meal_type: meal_type || null,
            goal: user.goal,
            best,
            dining_halls: ranked,
            restrictions_applied: restrictions.applied,
            unsupported_restrictions: restrictions.unsupported,
        };
        if (!best && restrictions.applied.length > 0) {
            body.message = recs.emptyMessage(restrictions.applied, meal_type);
        }
        res.json(body);
    } catch (err) {
        if (err && err.error === 'User not found') return res.status(404).json(err);
        res.status(500).json({ error: 'Database error', details: err.message || String(err) });
    }
});

// ============ MEAL TRACKING ENDPOINTS ============

// Initialize meal tracking database
const mealTrackingDbPath = path.join(DATA_DIR, 'meal_tracking.json');

// Helper function to read meal tracking data
function readMealTracking() {
    try {
        if (fs.existsSync(mealTrackingDbPath)) {
            const data = fs.readFileSync(mealTrackingDbPath, 'utf8');
            return JSON.parse(data);
        }
    } catch (e) {
        console.error('Error reading meal tracking data:', e);
    }
    return { meals: [] };
}

// Helper function to write meal tracking data
function writeMealTracking(data) {
    try {
        fs.writeFileSync(mealTrackingDbPath, JSON.stringify(data, null, 2));
        return true;
    } catch (e) {
        console.error('Error writing meal tracking data:', e);
        return false;
    }
}

// Log a consumed meal
app.post('/api/user/:userId/meals', (req, res) => {
    const userId = parseInt(req.params.userId);
    const { foods, meal_type, dining_hall, consumed_at } = req.body;

    if (!foods || !Array.isArray(foods) || foods.length === 0) {
        return res.status(400).json({ error: 'foods array is required' });
    }

    // Each food may carry a quantity (servings eaten, default 1); totals scale by it
    const badFood = foods.find((f) => !isValidQuantity(f));
    if (badFood) {
        return res.status(400).json({
            error: `quantity for "${badFood.name}" must be a number greater than 0 and at most ${MAX_QUANTITY}`
        });
    }

    const trackingData = readMealTracking();

    const mealEntry = {
        id: Date.now(),
        user_id: userId,
        meal_type: meal_type || 'Snack',
        dining_hall: dining_hall || 'Unknown',
        consumed_at: consumed_at || new Date().toISOString(),
        foods: foods,
        totals: computeTotals(foods)
    };

    trackingData.meals.push(mealEntry);

    if (writeMealTracking(trackingData)) {
        res.status(201).json({ success: true, meal: mealEntry });
    } else {
        res.status(500).json({ error: 'Failed to save meal' });
    }
});

// Get user's meal history
app.get('/api/user/:userId/meals', (req, res) => {
    const userId = parseInt(req.params.userId);
    const { date, limit } = req.query;

    const trackingData = readMealTracking();
    let userMeals = trackingData.meals.filter(m => m.user_id === userId);

    // Filter by date if provided (YYYY-MM-DD format)
    if (date) {
        userMeals = userMeals.filter(m => m.consumed_at.startsWith(date));
    }

    // Sort by most recent first
    userMeals.sort((a, b) => new Date(b.consumed_at) - new Date(a.consumed_at));

    // Apply limit if provided
    if (limit) {
        userMeals = userMeals.slice(0, parseInt(limit));
    }

    res.json({ meals: userMeals, count: userMeals.length });
});

// Get today's nutrition totals for user
app.get('/api/user/:userId/today-totals', (req, res) => {
    const userId = parseInt(req.params.userId);
    // Use local date instead of UTC to avoid timezone issues
    const now = new Date();
    const today = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`;

    const trackingData = readMealTracking();
    const todayMeals = trackingData.meals.filter(m =>
        m.user_id === userId && m.consumed_at.startsWith(today)
    );

    const totals = {
        calories: 0,
        protein: 0,
        fat: 0,
        carbs: 0,
        fiber: 0,
        meals_count: todayMeals.length
    };

    todayMeals.forEach(meal => {
        totals.calories += meal.totals.calories || 0;
        totals.protein += meal.totals.protein || 0;
        totals.fat += meal.totals.fat || 0;
        totals.carbs += meal.totals.carbs || 0;
        totals.fiber += meal.totals.fiber || 0;
    });

    res.json({ totals, date: today, meals: todayMeals });
});

// Delete a meal entry
app.delete('/api/user/:userId/meals/:mealId', (req, res) => {
    const userId = parseInt(req.params.userId);
    const mealId = parseInt(req.params.mealId);

    const trackingData = readMealTracking();
    const mealIndex = trackingData.meals.findIndex(m =>
        m.id === mealId && m.user_id === userId
    );

    if (mealIndex === -1) {
        return res.status(404).json({ error: 'Meal not found' });
    }

    trackingData.meals.splice(mealIndex, 1);

    if (writeMealTracking(trackingData)) {
        res.json({ success: true, message: 'Meal deleted' });
    } else {
        res.status(500).json({ error: 'Failed to delete meal' });
    }
});

// Health check
app.get('/health', (req, res) => {
    res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// Start server (tests import the app and listen on their own port)
if (require.main === module) {
    app.listen(PORT, () => {
        console.log(`Server running on http://localhost:${PORT}`);
        console.log(`Authentication endpoints available at:`);
        console.log(`  POST http://localhost:${PORT}/api/auth/register`);
        console.log(`  POST http://localhost:${PORT}/api/auth/login`);
        console.log(`  PUT  http://localhost:${PORT}/api/user/:userId/profile`);
        console.log(`  GET  http://localhost:${PORT}/api/user/:userId/profile`);
    });
}

module.exports = app;
