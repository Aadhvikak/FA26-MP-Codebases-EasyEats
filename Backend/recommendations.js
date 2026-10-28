// Dietary-restriction filtering and goal-aware ranking for food recommendations.
//
// Safety rule: a food is only kept when we can POSITIVELY show it meets every
// restriction (a matching dietary tag, or nutrient numbers within the limit).
// Foods with no label for a restriction are excluded, never assumed safe.

// Restriction (as saved in the user's profile) -> what a food must satisfy.
//   tag:      the food's dietary_tags must include it
//   nutrient: the food's numbers must be within the limit (per serving)
const RESTRICTION_RULES = {
    'Vegetarian': { tag: 'vegetarian' },
    'Vegan': { tag: 'vegan' },
    'Gluten-Free': { tag: 'gluten-free' },
    'Dairy-Free': { tag: 'dairy-free' },
    'Nut Allergy': { tag: 'nut-free' },
    'Shellfish Allergy': { tag: 'shellfish-free' },
    'Egg Allergy': { tag: 'egg-free' },
    'Soy Allergy': { tag: 'soy-free' },
    'Halal': { tag: 'halal' },
    'Kosher': { tag: 'kosher' },
    // Sodium is stored in grams: 0.14 g = 140 mg, the FDA "low sodium" limit
    'Low Sodium': { nutrient: (f) => (f.sodium || 0) <= 0.14 },
    'Low Sugar': { nutrient: (f) => (f.sugars || 0) <= 5 },
    // Net carbs (carbs minus fiber) of at most 10 g per serving
    'Keto': { nutrient: (f) => (f.total_carbohydrate || 0) - (f.dietary_fiber || 0) <= 10 },
    // 'Paleo' has no rule: we cannot tell it from menu data, so it is reported as unsupported
};

function parseTags(value) {
    if (Array.isArray(value)) return new Set(value);
    if (!value) return new Set();
    return new Set(String(value).split(',').map((t) => t.trim()).filter(Boolean));
}

// Does the food meet one restriction? Unknown restrictions return null.
function meetsRestriction(food, restriction) {
    const rule = RESTRICTION_RULES[restriction];
    if (!rule) return null;
    if (rule.tag) return parseTags(food.dietary_tags).has(rule.tag);
    return rule.nutrient(food);
}

// Keep only foods that meet every supported restriction.
function applyRestrictions(foods, restrictions) {
    const requested = (restrictions || []).filter(Boolean);
    const applied = requested.filter((r) => RESTRICTION_RULES[r]);
    const unsupported = requested.filter((r) => !RESTRICTION_RULES[r]);

    const kept = foods.filter((food) => applied.every((r) => meetsRestriction(food, r)));
    return { foods: kept, applied, unsupported, excluded: foods.length - kept.length };
}

// Collapse rows that share a name (the same dish on different days) into one food.
// A dietary tag survives only if every row carries it, so a dish whose recipe
// changed between days is never reported as safer than its least safe version.
function mergeByName(rows) {
    const byName = new Map();
    for (const row of rows) {
        const existing = byName.get(row.name);
        if (!existing) {
            byName.set(row.name, { ...row, dietary_tags: parseTags(row.dietary_tags) });
            continue;
        }
        const rowTags = parseTags(row.dietary_tags);
        existing.dietary_tags = new Set([...existing.dietary_tags].filter((t) => rowTags.has(t)));
    }
    return [...byName.values()].map((f) => ({ ...f, dietary_tags: [...f.dietary_tags].sort().join(',') || null }));
}

// How well a food fits the user's goal. Higher is better.
function scoreFood(food, goal, targetCaloriesPerMeal) {
    const calories = food.calories || 0;
    if (calories <= 0) return -Infinity;

    const proteinRatio = ((food.protein || 0) * 4) / calories;      // share of calories from protein
    const fatRatio = ((food.total_fat || 0) * 9) / calories;        // share of calories from fat
    const fiberPer100 = ((food.dietary_fiber || 0) / calories) * 100;
    const target = targetCaloriesPerMeal || 667;
    const portion = calories / target;                               // 1 = one whole meal's calories

    const g = (goal || '').toLowerCase();
    if (g.includes('los')) {
        // Losing weight: lean, protein-dense, filling, and not a calorie bomb
        return 2 * proteinRatio - fatRatio + 0.1 * fiberPer100 - 0.5 * Math.max(0, portion - 0.5);
    }
    if (g.includes('gain')) {
        // Gaining weight: protein-rich and calorie-dense
        return 2 * proteinRatio + 0.8 * Math.min(portion, 1) + 0.5 * Math.min((food.protein || 0) / 30, 1);
    }
    // Becoming fit / no goal: balanced, protein-forward, moderate calories
    return 1.5 * proteinRatio - 0.7 * fatRatio + 0.1 * fiberPer100 - 0.3 * Math.abs(portion - 0.5);
}

function rankFoods(foods, goal, targetCaloriesPerMeal) {
    return foods
        .filter((f) => (f.calories || 0) > 0)
        .map((f) => ({ food: f, score: scoreFood(f, goal, targetCaloriesPerMeal) }))
        .sort((a, b) => b.score - a.score || a.food.name.localeCompare(b.food.name))
        .map((x) => x.food);
}

// Human-readable explanation for an empty result.
function emptyMessage(restrictions, mealType) {
    const list = restrictions.join(', ');
    const meal = mealType ? ` for ${mealType}` : '';
    return `No foods here meet your dietary restrictions (${list})${meal}, so we aren't recommending anything. ` +
        'Foods without dietary labels are left out to keep you safe.';
}

// Summarize how well one dining hall serves this user. Used to pick the best hall.
function summarizeHall(foods, goal, targetCaloriesPerMeal, restrictions) {
    const { foods: safe, applied, unsupported } = applyRestrictions(foods, restrictions);
    const ranked = rankFoods(safe, goal, targetCaloriesPerMeal);
    const top = ranked.slice(0, 5);
    const topScores = top.map((f) => scoreFood(f, goal, targetCaloriesPerMeal));
    const goalScore = topScores.length ? topScores.reduce((a, b) => a + b, 0) / topScores.length : null;

    return {
        matching_count: ranked.length,
        goal_score: goalScore,
        top_foods: top.slice(0, 3).map((f) => f.name),
        restrictions_applied: applied,
        unsupported_restrictions: unsupported,
    };
}

// Rank halls: those with enough matching foods to build a meal come first, ordered by how well
// their best foods fit the goal; halls with nothing safe sort last.
function rankHalls(summaries) {
    const MIN_FOODS_FOR_A_MEAL = 3;
    return [...summaries].sort((a, b) => {
        const aOk = a.matching_count >= MIN_FOODS_FOR_A_MEAL;
        const bOk = b.matching_count >= MIN_FOODS_FOR_A_MEAL;
        if (aOk !== bOk) return aOk ? -1 : 1;
        if ((a.matching_count > 0) !== (b.matching_count > 0)) return a.matching_count > 0 ? -1 : 1;
        const diff = (b.goal_score ?? -Infinity) - (a.goal_score ?? -Infinity);
        return diff || b.matching_count - a.matching_count;
    });
}

module.exports = {
    RESTRICTION_RULES,
    parseTags,
    meetsRestriction,
    applyRestrictions,
    mergeByName,
    scoreFood,
    rankFoods,
    emptyMessage,
    summarizeHall,
    rankHalls,
};
