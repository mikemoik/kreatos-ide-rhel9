#include "customers/customer.hpp"

#include <algorithm>
#include <cctype>

namespace customers {

void validate(const Customer &customer) {
  const bool blank = std::all_of(customer.name.begin(), customer.name.end(),
                                 [](unsigned char c) { return std::isspace(c); });
  if (blank)
    throw ValidationError("name must not be empty");

  const auto at = customer.email.find('@');
  if (at == std::string::npos || at == 0 || at + 1 == customer.email.size() ||
      customer.email.find('@', at + 1) != std::string::npos)
    throw ValidationError("invalid email: " + customer.email);
}

std::string email_domain(const Customer &customer) {
  const auto at = customer.email.find('@');
  return at == std::string::npos ? "" : customer.email.substr(at + 1);
}

} // namespace customers
