// Minimal JSON for the database file:
//   {"customers": [{"id": 1, "name": "…", "email": "…", "city": "…"}, …]}
// Just enough for this sample: objects, arrays, strings and integers.
#pragma once

#include "customers/customer.hpp"

#include <string>
#include <vector>

namespace customers::json {

/// A parse error, with the byte offset where it happened.
class ParseError : public std::runtime_error {
public:
  using std::runtime_error::runtime_error;
};

std::vector<Customer> parse(const std::string &text);
std::string serialize(const std::vector<Customer> &list);

/// `s` as a JSON string literal, quotes included.
std::string quote(const std::string &s);

} // namespace customers::json
