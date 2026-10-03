import unittest

from customerdb.models import Customer
from customerdb.report import customers_per_city, email_domains
from customerdb.search import matches

CUSTOMERS = [
    Customer(1, "Ada Lovelace", "ada@example.com", "London"),
    Customer(2, "Grace Hopper", "grace@navy.mil", "Arlington"),
    Customer(3, "Alan Turing", "alan@example.com", "London"),
    Customer(4, "Nobody", "no@body.org"),
]


class SearchTest(unittest.TestCase):
    def test_case_and_whitespace(self) -> None:
        self.assertTrue(matches(CUSTOMERS[0], "  ada   LOVE "))
        self.assertTrue(matches(CUSTOMERS[1], "NAVY"))
        self.assertTrue(matches(CUSTOMERS[2], "london"))
        self.assertFalse(matches(CUSTOMERS[3], "london"))


class ReportTest(unittest.TestCase):
    def test_customers_per_city(self) -> None:
        self.assertEqual(
            customers_per_city(CUSTOMERS), {"London": 2, "(unknown)": 1, "Arlington": 1}
        )

    def test_email_domains(self) -> None:
        self.assertEqual(email_domains(CUSTOMERS), ["body.org", "example.com", "navy.mil"])


if __name__ == "__main__":
    unittest.main()
