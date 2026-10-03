// The Customer record and its validation.
#pragma once

#include <stdexcept>
#include <string>

namespace customers {

struct Customer {
  int id = 0;
  std::string name;
  std::string email;
  std::string city;
};

/// A customer field has an invalid value.
class ValidationError : public std::runtime_error {
public:
  using std::runtime_error::runtime_error;
};

/// Throws ValidationError if the name is blank or the email has no single '@'.
void validate(const Customer &customer);

/// The part of the email after '@' ("" if there is none).
std::string email_domain(const Customer &customer);

} // namespace customers
