// Matching customers against a search text.
#pragma once

#include "customers/customer.hpp"

#include <string>
#include <vector>

namespace customers {

/// Lower case, runs of whitespace collapsed to one space, trimmed.
std::string normalize(const std::string &text);

/// Case-insensitive substring match on name, email or city.
bool matches(const Customer &customer, const std::string &text);

/// The customers in `list` that match `text`, in order.
std::vector<Customer> filter(const std::vector<Customer> &list, const std::string &text);

} // namespace customers
