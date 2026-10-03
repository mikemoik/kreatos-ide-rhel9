// Summaries over all customers.
#pragma once

#include "customers/customer.hpp"

#include <set>
#include <string>
#include <utility>
#include <vector>

namespace customers {

/// (city, count), most customers first, then by name; "" counts as "(unknown)".
std::vector<std::pair<std::string, int>> customers_per_city(const std::vector<Customer> &list);

/// The distinct email domains, sorted.
std::set<std::string> email_domains(const std::vector<Customer> &list);

/// Human-readable report of the two above.
std::string render_report(const std::vector<Customer> &list);

} // namespace customers
