#include "check.hpp"
#include "customers/customer_db.hpp"

#include <filesystem>

using namespace customers;

int main() {
  namespace fs = std::filesystem;
  const fs::path dir = fs::temp_directory_path() / "customers-cpp-test";
  fs::remove_all(dir);
  const fs::path file = dir / "customers.json";

  // add, save, reload (with characters that need escaping)
  {
    CustomerDB db(file);
    db.add("Ada Lovelace", "ada@example.com", "London");
    db.add("Grace \"Amazing\" Hopper", "grace@navy.mil", "Arlington\\VA");
    db.save();
  }
  {
    CustomerDB db(file);
    CHECK(db.all().size() == 2);
    CHECK(db.get(2)->name == "Grace \"Amazing\" Hopper");
    CHECK(db.get(2)->city == "Arlington\\VA");
  }

  // update, find, delete; ids continue after the highest
  {
    CustomerDB db(file);
    Customer ada = *db.get(1);
    ada.city = "Paris";
    CHECK(db.update(ada));
    CHECK(db.get(1)->city == "Paris");
    CHECK(db.find("NAVY").size() == 1);
    CHECK(db.remove(1));
    CHECK(!db.remove(1));
    CHECK(db.add("Alan Turing", "alan@example.com").id == 3);
  }

  // validation
  {
    CustomerDB db(file);
    CHECK_THROWS(db.add("Nobody", "not-an-email"), ValidationError);
    CHECK_THROWS(db.add("  ", "a@b"), ValidationError);
    Customer grace = *db.get(2);
    grace.email = "a@b@c";
    CHECK_THROWS(db.update(grace), ValidationError);
  }

  fs::remove_all(dir);
  return 0;
}
