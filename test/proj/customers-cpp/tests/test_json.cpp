#include "check.hpp"
#include "customers/json.hpp"

using namespace customers;

int main() {
  // round trip, including characters that need escaping
  const std::vector<Customer> list = {
      {1, "Ada \"the first\" Lovelace", "ada@example.com", "London"},
      {7, "Tab\tand\\backslash", "t@x", ""},
  };
  const std::vector<Customer> back = json::parse(json::serialize(list));
  CHECK(back.size() == 2);
  CHECK(back[0].name == list[0].name);
  CHECK(back[1].id == 7);
  CHECK(back[1].name == list[1].name);

  // empty database
  CHECK(json::parse(json::serialize({})).empty());

  // errors
  CHECK_THROWS(json::parse(""), json::ParseError);
  CHECK_THROWS(json::parse(R"({"people": []})"), json::ParseError);
  CHECK_THROWS(json::parse(R"({"customers": [{"id": "x"}]})"), json::ParseError);
  CHECK_THROWS(json::parse(R"({"customers": []} extra)"), json::ParseError);

  CHECK(json::quote("a\"b") == R"("a\"b")");
  return 0;
}
