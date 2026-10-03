#include "customers/storage.hpp"

#include "customers/json.hpp"

#include <fstream>
#include <sstream>

namespace customers {

JsonStore::JsonStore(std::filesystem::path path) : path_(std::move(path)) {}

std::vector<Customer> JsonStore::load() const {
  std::ifstream in(path_);
  if (!in)
    return {}; // new database
  std::stringstream text;
  text << in.rdbuf();
  try {
    return json::parse(text.str());
  } catch (const json::ParseError &e) {
    throw json::ParseError(path_.string() + ": " + e.what());
  }
}

void JsonStore::save(const std::vector<Customer> &list) const {
  if (path_.has_parent_path())
    std::filesystem::create_directories(path_.parent_path());
  std::filesystem::path tmp = path_;
  tmp += ".tmp";
  {
    std::ofstream out(tmp, std::ios::trunc);
    if (!out)
      throw std::runtime_error("cannot write " + tmp.string());
    out << json::serialize(list);
  }
  std::filesystem::rename(tmp, path_); // never a half-written db
}

} // namespace customers
