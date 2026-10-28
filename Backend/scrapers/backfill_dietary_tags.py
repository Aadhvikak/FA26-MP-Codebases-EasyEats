"""
Add the dietary columns to an existing nutrition_data.db and tag the rows that are
already in it.

The data scraped before dietary labels were collected only has item names to go on,
so existing rows are tagged from explicit name markers (Vegan, Vegetarian, Jain,
Halal, ...) and marked tags_source='inferred'. Re-run the scraper and
load_to_db.py to replace them with the dining hall's own allergen and diet labels.

Usage: python backfill_dietary_tags.py [path/to/nutrition_data.db]
"""
import os
import sqlite3
import sys

from dietary_tags import derive_tags, serialize_tags

NEW_COLUMNS = (
    ('ingredients', 'TEXT'),
    ('allergens', 'TEXT'),
    ('dietary_tags', 'TEXT'),
    ('tags_source', 'TEXT'),
)


def add_missing_columns(conn):
    existing = {row[1] for row in conn.execute('PRAGMA table_info(nutrition_data)')}
    for column, column_type in NEW_COLUMNS:
        if column not in existing:
            conn.execute(f'ALTER TABLE nutrition_data ADD COLUMN {column} {column_type}')


def backfill(db_file):
    conn = sqlite3.connect(db_file)
    add_missing_columns(conn)

    # Rows with scraped labels are authoritative and never overwritten
    rows = conn.execute(
        "SELECT id, name FROM nutrition_data WHERE tags_source IS NULL OR tags_source = 'inferred'"
    ).fetchall()

    tagged = 0
    for row_id, name in rows:
        tags, source = derive_tags(name)
        conn.execute(
            'UPDATE nutrition_data SET dietary_tags = ?, tags_source = ? WHERE id = ?',
            (serialize_tags(tags), source, row_id),
        )
        tagged += 1 if tags else 0

    conn.commit()
    total = conn.execute('SELECT COUNT(*) FROM nutrition_data').fetchone()[0]
    conn.close()
    print(f'Tagged {tagged} of {len(rows)} rows ({total} total) in {db_file}')


if __name__ == '__main__':
    default_db = os.path.join(os.path.dirname(__file__), '..', 'data', 'nutrition_data.db')
    backfill(sys.argv[1] if len(sys.argv) > 1 else default_db)
