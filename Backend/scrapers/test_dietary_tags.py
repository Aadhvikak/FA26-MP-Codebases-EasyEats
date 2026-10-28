import os
import sqlite3
import tempfile
import unittest

from backfill_dietary_tags import backfill
from dietary_tags import derive_tags, serialize_tags


class DeriveTagsTest(unittest.TestCase):
    def test_unlabeled_item_gets_no_tags(self):
        self.assertEqual(derive_tags('Cauliflower'), ([], None))
        self.assertEqual(derive_tags('Chicken Noodle Soup'), ([], None))

    def test_name_markers_are_inferred(self):
        self.assertEqual(derive_tags('Halal Beef Lasagna'), (['halal'], 'inferred'))
        self.assertEqual(derive_tags('Sauce Marinara Jain'), (['vegetarian'], 'inferred'))
        self.assertEqual(derive_tags('Chocolate Chip Pancakes (JAIN)'), (['vegetarian'], 'inferred'))

    def test_vegan_implies_vegetarian_dairy_free_and_egg_free(self):
        tags, source = derive_tags('Vegan Meatball')
        self.assertEqual(tags, ['dairy-free', 'egg-free', 'vegan', 'vegetarian'])
        self.assertEqual(source, 'inferred')

    def test_declared_allergens_rule_out_free_tags(self):
        tags, source = derive_tags('Mac and Cheese', allergens='Milk, Wheat')
        self.assertEqual(source, 'scraped')
        self.assertNotIn('dairy-free', tags)
        self.assertNotIn('gluten-free', tags)
        self.assertIn('egg-free', tags)
        self.assertIn('nut-free', tags)

    def test_tree_nuts_and_peanuts_both_rule_out_nut_free(self):
        self.assertNotIn('nut-free', derive_tags('x', allergens='Tree Nuts')[0])
        self.assertNotIn('nut-free', derive_tags('x', allergens='Peanuts')[0])

    def test_declared_none_means_free_of_everything(self):
        tags, source = derive_tags('Steamed Rice', allergens='No allergens listed')
        self.assertEqual(source, 'scraped')
        for tag in ('gluten-free', 'dairy-free', 'nut-free', 'shellfish-free', 'egg-free', 'soy-free'):
            self.assertIn(tag, tags)

    def test_missing_allergen_info_is_unknown_not_safe(self):
        tags, _ = derive_tags('Mystery Casserole', allergens=None)
        self.assertEqual(tags, [])

    def test_site_labels_become_tags(self):
        tags, source = derive_tags('Stir Fry', labels=['Vegan', 'Some Unknown Icon'])
        self.assertIn('vegan', tags)
        self.assertEqual(source, 'scraped')

    def test_serialize(self):
        self.assertEqual(serialize_tags(['halal', 'vegan']), 'halal,vegan')
        self.assertIsNone(serialize_tags([]))


class BackfillTest(unittest.TestCase):
    def test_backfill_adds_columns_and_tags_rows_but_keeps_scraped_rows(self):
        with tempfile.TemporaryDirectory() as tmp:
            db = os.path.join(tmp, 'n.db')
            conn = sqlite3.connect(db)
            conn.execute('CREATE TABLE nutrition_data (id INTEGER PRIMARY KEY, name TEXT)')
            conn.executemany('INSERT INTO nutrition_data (name) VALUES (?)',
                             [('Vegan Meatball',), ('Cauliflower',)])
            conn.commit()
            conn.close()

            backfill(db)

            conn = sqlite3.connect(db)
            rows = dict(conn.execute('SELECT name, dietary_tags FROM nutrition_data'))
            self.assertEqual(rows['Vegan Meatball'], 'dairy-free,egg-free,vegan,vegetarian')
            self.assertIsNone(rows['Cauliflower'])

            conn.execute("UPDATE nutrition_data SET dietary_tags='gluten-free', tags_source='scraped' "
                         "WHERE name='Cauliflower'")
            conn.commit()
            conn.close()

            backfill(db)  # idempotent, and must not overwrite scraped labels

            conn = sqlite3.connect(db)
            rows = dict(conn.execute('SELECT name, dietary_tags FROM nutrition_data'))
            self.assertEqual(rows['Cauliflower'], 'gluten-free')
            conn.close()


if __name__ == '__main__':
    unittest.main()
