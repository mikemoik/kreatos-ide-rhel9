#include "customers/search.hpp"

#include <cctype>
#include <sstream>

namespace customers {

std::string normalize(const std::string &text) {
  std::istringstream words(text);
  std::string word, out;
  while (words >> word) {
    if (!out.empty())
      out += ' ';
    for (const char c : word)
      out += static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
  }
  return out;
}

bool matches(const Customer &customer, const std::string &text) {
  const std::string needle = normalize(text);
  for (const std::string *field : {&customer.name, &customer.email, &customer.city})
    if (normalize(*field).find(needle) != std::string::npos)
      return true;
  return false;
}

std::vector<Customer> filter(const std::vector<Customer> &list, const std::string &text) {
  std::vector<Customer> out;
  for (const Customer &c : list)
    if (matches(c, text))
      out.push_back(c);
  return out;
}

} // namespace customers
