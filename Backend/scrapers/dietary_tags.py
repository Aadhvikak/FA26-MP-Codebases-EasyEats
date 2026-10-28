"""
Dietary tag derivation shared by the scraper, the DB loader and the backfill script.

Tags are POSITIVE claims ("this item is vegan", "this item contains no gluten").
An item with no tag for a restriction is treated as unsafe for that restriction, so
anything we cannot verify is left out of recommendations rather than guessed at.

Tags come from two places:
  * scraped: the dining hall's own allergen declaration and diet icons (reliable)
  * inferred: explicit markers in the item name such as "Vegan", "Halal" or "Jain"
    (only used when no scraped information exists for the item)
"""
import re

ALL_TAGS = (
    'vegetarian', 'vegan', 'gluten-free', 'dairy-free', 'nut-free',
    'shellfish-free', 'egg-free', 'soy-free', 'halal', 'kosher',
)

# A tag that implies other tags (vegan food has no dairy, eggs or meat)
TAG_IMPLICATIONS = {
    'vegan': ('vegetarian', 'dairy-free', 'egg-free'),
}

# Free-of tag -> allergen words that rule it out when they appear in the declared allergens
ALLERGEN_KEYWORDS = {
    'gluten-free': ('wheat', 'gluten', 'barley', 'rye'),
    'dairy-free': ('milk', 'dairy', 'lactose'),
    'nut-free': ('nut', 'almond', 'cashew', 'pecan', 'walnut', 'pistachio', 'hazelnut'),
    'shellfish-free': ('shellfish', 'crustacean', 'shrimp', 'crab', 'lobster', 'mollus'),
    'egg-free': ('egg',),
    'soy-free': ('soy',),
}

# Diet icon / label text -> tag
LABEL_TAGS = {
    'vegan': 'vegan',
    'vegetarian': 'vegetarian',
    'jain': 'vegetarian',
    'halal': 'halal',
    'kosher': 'kosher',
    'gluten free': 'gluten-free',
    'gluten-free': 'gluten-free',
    'dairy free': 'dairy-free',
    'dairy-free': 'dairy-free',
}

# Explicit markers in an item name -> tag
NAME_MARKERS = (
    (re.compile(r'\bvegan\b', re.I), 'vegan'),
    (re.compile(r'\bvegetarian\b', re.I), 'vegetarian'),
    (re.compile(r'\bjain\b', re.I), 'vegetarian'),
    (re.compile(r'\bhalal\b', re.I), 'halal'),
    (re.compile(r'\bkosher\b', re.I), 'kosher'),
    (re.compile(r'\bgluten[- ]free\b', re.I), 'gluten-free'),
    (re.compile(r'\bdairy[- ]free\b', re.I), 'dairy-free'),
)


def _expand(tags):
    """Add the tags implied by the ones already present."""
    expanded = set(tags)
    for tag in tags:
        expanded.update(TAG_IMPLICATIONS.get(tag, ()))
    return expanded


def _tags_from_allergens(allergens):
    """Free-of tags for every allergen group not declared in the allergen text."""
    declared = [a.strip().lower() for a in re.split(r'[,;/]', allergens)]
    # "No allergens listed" is what the scraper writes when the site declares none
    declared = [a for a in declared if a and a != 'none' and not a.startswith('no ')]
    return {
        tag for tag, words in ALLERGEN_KEYWORDS.items()
        if not any(word in item for item in declared for word in words)
    }


def derive_tags(name, allergens=None, labels=None):
    """
    Returns (tags, source) where tags is a sorted list and source is
    'scraped', 'inferred' or None (no information at all).

    allergens: the declared allergen text, or None when the site gave no allergen
               information (unknown, which yields no free-of tags).
    labels:    diet icon / label strings found on the item, or None.
    """
    tags = set()
    has_scraped = False

    if allergens is not None and str(allergens).strip():
        has_scraped = True
        tags |= _tags_from_allergens(str(allergens))

    for label in labels or []:
        tag = LABEL_TAGS.get(str(label).strip().lower())
        if tag:
            has_scraped = True
            tags.add(tag)

    name_tags = {tag for pattern, tag in NAME_MARKERS if pattern.search(name or '')}
    tags |= name_tags

    tags = _expand(tags)
    if not tags:
        return [], None
    return sorted(tags), 'scraped' if has_scraped else 'inferred'


def serialize_tags(tags):
    """Tags as stored in the DB: comma separated, or None when there are none."""
    return ','.join(tags) if tags else None
