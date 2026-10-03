#include "check.hpp"
#include "customers/report.hpp"
#include "customers/search.hpp"

using namespace customers;

int main() {
  const std::vector<Customer> list = {
      {1, "Ada Lovelace", "ada@example.com", "London"},
      {2, "Grace Hopper", "grace@navy.mil", "Arlington"},
      {3, "Alan Turing", "alan@example.com", "London"},
      {4, "Nobody", "no@body.org", ""},
  };

  // search
  CHECK(normalize("  Ada   LOVE ") == "ada love");
  CHECK(matches(list[0], "  ada   LOVE "));
  CHECK(matches(list[1], "NAVY"));
  CHECK(!matches(list[3], "london"));
  CHECK(filter(list, "london").size() == 2);

  // report
  const auto cities = customers_per_city(list);
  CHECK(cities.size() == 3);
  CHECK(cities[0].first == "London" && cities[0].second == 2);
  CHECK(cities[1].first == "(unknown)");
  const auto domains = email_domains(list);
  CHECK(domains == std::set<std::string>({"body.org", "example.com", "navy.mil"}));
  CHECK(render_report(list).find("4 customers") == 0);
  return 0;
}
