// CustomerDB: the customers in memory, persisted through a JsonStore.
#pragma once

#include "customers/customer.hpp"
#include "customers/storage.hpp"

#include <map>
#include <optional>
#include <string>
#include <vector>

namespace customers {

class CustomerDB {
public:
  /// Loads the whole file if it exists; throws json::ParseError on bad JSON.
  explicit CustomerDB(std::filesystem::path path);

  /// Validates, assigns the next id and adds; throws ValidationError.
  Customer add(std::string name, std::string email, std::string city = "");
  std::optional<Customer> get(int id) const;
  /// Replaces name/email/city of an existing customer; false if the id is unknown.
  bool update(const Customer &customer);
  bool remove(int id);
  /// All customers, ordered by id.
  std::vector<Customer> all() const;
  std::vector<Customer> find(const std::string &text) const;
  void save() const;

private:
  JsonStore store_;
  std::map<int, Customer> customers_;
};

} // namespace customers
