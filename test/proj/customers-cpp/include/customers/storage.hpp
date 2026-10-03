// Reads and writes the list of customers as one JSON file.
#pragma once

#include "customers/customer.hpp"

#include <filesystem>
#include <vector>

namespace customers {

class JsonStore {
public:
  explicit JsonStore(std::filesystem::path path);

  /// All customers in the file; empty if the file does not exist yet.
  std::vector<Customer> load() const;
  /// Writes atomically: temp file in the same directory, then rename.
  void save(const std::vector<Customer> &list) const;

  const std::filesystem::path &path() const { return path_; }

private:
  std::filesystem::path path_;
};

} // namespace customers
