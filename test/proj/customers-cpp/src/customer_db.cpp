#include "customers/customer_db.hpp"

#include "customers/search.hpp"

namespace customers {

CustomerDB::CustomerDB(std::filesystem::path path) : store_(std::move(path)) {
  for (Customer &c : store_.load())
    customers_[c.id] = std::move(c);
}

Customer CustomerDB::add(std::string name, std::string email, std::string city) {
  const int id = customers_.empty() ? 1 : customers_.rbegin()->first + 1;
  Customer c{id, std::move(name), std::move(email), std::move(city)};
  validate(c);
  customers_[id] = c;
  return c;
}

std::optional<Customer> CustomerDB::get(int id) const {
  const auto it = customers_.find(id);
  if (it == customers_.end())
    return std::nullopt;
  return it->second;
}

bool CustomerDB::update(const Customer &customer) {
  const auto it = customers_.find(customer.id);
  if (it == customers_.end())
    return false;
  validate(customer);
  it->second = customer;
  return true;
}

bool CustomerDB::remove(int id) { return customers_.erase(id) > 0; }

std::vector<Customer> CustomerDB::all() const {
  std::vector<Customer> out;
  out.reserve(customers_.size());
  for (const auto &[id, c] : customers_)
    out.push_back(c);
  return out;
}

std::vector<Customer> CustomerDB::find(const std::string &text) const {
  return filter(all(), text);
}

void CustomerDB::save() const { store_.save(all()); }

} // namespace customers
