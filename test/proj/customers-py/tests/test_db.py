import json
import tempfile
import unittest
from pathlib import Path

from customerdb import CustomerDB, ValidationError


class CustomerDBTest(unittest.TestCase):
    def setUp(self) -> None:
        self.dir = tempfile.TemporaryDirectory()
        self.path = Path(self.dir.name) / "customers.json"

    def tearDown(self) -> None:
        self.dir.cleanup()

    def test_add_save_reload(self) -> None:
        db = CustomerDB(self.path)
        db.add("Ada Lovelace", "ada@example.com", "London")
        db.add("Alan Turing", "alan@example.com")
        db.save()

        again = CustomerDB(self.path)
        self.assertEqual([c.name for c in again.all()], ["Ada Lovelace", "Alan Turing"])
        self.assertEqual(json.loads(self.path.read_text())["customers"][0]["city"], "London")

    def test_ids_continue_after_delete(self) -> None:
        db = CustomerDB(self.path)
        db.add("a", "a@x")
        b = db.add("b", "b@x")
        self.assertTrue(db.delete(b.id))
        self.assertEqual(db.add("c", "c@x").id, 2)

    def test_update(self) -> None:
        db = CustomerDB(self.path)
        c = db.add("Ada", "ada@example.com")
        db.update(c.id, city="Paris")
        self.assertEqual(db.get(c.id).city, "Paris")
        with self.assertRaises(AttributeError):
            db.update(c.id, id=7)

    def test_validation(self) -> None:
        db = CustomerDB(self.path)
        with self.assertRaises(ValidationError):
            db.add("Ada", "not-an-email")
        c = db.add("Ada", "ada@example.com")
        with self.assertRaises(ValidationError):
            db.update(c.id, name="  ")


if __name__ == "__main__":
    unittest.main()
