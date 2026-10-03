#include "cli.hpp"

#include "customers/customer_db.hpp"
#include "customers/report.hpp"

#include <cstdio>
#include <iostream>

namespace cli {

namespace {

using customers::Customer;
using customers::CustomerDB;

void show(const Customer &c) {
  std::printf("%4d  %-20s %-28s %s\n", c.id, c.name.c_str(), c.email.c_str(), c.city.c_str());
}

int usage() {
  std::cerr << "usage: customers [--db FILE] {list | report | add NAME EMAIL [CITY] | get ID |\n"
               "                  update ID name|email|city VALUE | delete ID | find TEXT}\n";
  return 2;
}

int not_found(int id) {
  std::cerr << "no customer " << id << "\n";
  return 1;
}

int update(CustomerDB &db, int id, const std::string &field, const std::string &value) {
  auto c = db.get(id);
  if (!c)
    return not_found(id);
  if (field == "name")
    c->name = value;
  else if (field == "email")
    c->email = value;
  else if (field == "city")
    c->city = value;
  else
    return usage();
  db.update(*c);
  db.save();
  show(*c);
  return 0;
}

int dispatch(CustomerDB &db, const std::vector<std::string> &args) {
  const std::string &cmd = args[0];
  const std::size_t n = args.size();
  if (cmd == "list" && n == 1) {
    for (const Customer &c : db.all())
      show(c);
  } else if (cmd == "report" && n == 1) {
    std::cout << customers::render_report(db.all());
  } else if (cmd == "add" && (n == 3 || n == 4)) {
    show(db.add(args[1], args[2], n == 4 ? args[3] : ""));
    db.save();
  } else if (cmd == "get" && n == 2) {
    const int id = std::stoi(args[1]);
    const auto c = db.get(id);
    if (!c)
      return not_found(id);
    show(*c);
  } else if (cmd == "update" && n == 4) {
    return update(db, std::stoi(args[1]), args[2], args[3]);
  } else if (cmd == "delete" && n == 2) {
    const int id = std::stoi(args[1]);
    if (!db.remove(id))
      return not_found(id);
    db.save();
  } else if (cmd == "find" && n == 2) {
    for (const Customer &c : db.find(args[1]))
      show(c);
  } else {
    return usage();
  }
  return 0;
}

} // namespace

int run(std::vector<std::string> args) {
  std::string db_path = "customers.json";
  if (args.size() >= 2 && args[0] == "--db") {
    db_path = args[1];
    args.erase(args.begin(), args.begin() + 2);
  }
  if (args.empty())
    return usage();
  try {
    CustomerDB db(db_path);
    return dispatch(db, args);
  } catch (const std::exception &e) {
    std::cerr << "error: " << e.what() << "\n";
    return 1;
  }
}

} // namespace cli
