// Nutrition totals for a logged meal, scaled by how much of each food was eaten.

const MAX_QUANTITY = 50;

// Number of servings eaten of one food; foods logged before quantities existed count as 1.
function quantityOf(food) {
    return food.quantity === undefined || food.quantity === null ? 1 : food.quantity;
}

function isValidQuantity(food) {
    const q = quantityOf(food);
    return typeof q === 'number' && Number.isFinite(q) && q > 0 && q <= MAX_QUANTITY;
}

const round = (n) => Math.round(n * 100) / 100;

function computeTotals(foods) {
    const sum = (field) => round(foods.reduce((total, f) => total + (f[field] || 0) * quantityOf(f), 0));
    return {
        calories: sum('calories'),
        protein: sum('protein'),
        fat: sum('total_fat'),
        carbs: sum('total_carbohydrate'),
        fiber: sum('dietary_fiber'),
    };
}

module.exports = { MAX_QUANTITY, quantityOf, isValidQuantity, computeTotals };
