#include "customers/report.hpp"

#include <algorithm>
#include <cstdio>
#include <map>

namespace customers {

std::vector<std::pair<std::string, int>> customers_per_city(const std::vector<Customer> &list) {
  std::map<std::string, int> counts;
  for (const Customer &c : list)
    ++counts[c.city.empty() ? "(unknown)" : c.city];

  std::vector<std::pair<std::string, int>> out(counts.begin(), counts.end());
  std::stable_sort(out.begin(), out.end(),
                   [](const auto &a, const auto &b) { return a.second > b.second; });
  return out;
}

std::set<std::string> email_domains(const std::vector<Customer> &list) {
  std::set<std::string> out;
  for (const Customer &c : list)
    out.insert(email_domain(c));
  return out;
}

std::string render_report(const std::vector<Customer> &list) {
  std::string out = std::to_string(list.size()) + " customers\n\nper city:\n";
  char line[128];
  for (const auto &[city, count] : customers_per_city(list)) {
    std::snprintf(line, sizeof line, "  %-20s %d\n", city.c_str(), count);
    out += line;
  }
  out += "\nemail domains:";
  const char *sep = " ";
  for (const std::string &domain : email_domains(list)) {
    out += sep + domain;
    sep = ", ";
  }
  return out + "\n";
}

} // namespace customers
