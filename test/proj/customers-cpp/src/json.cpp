#include "customers/json.hpp"

#include <cctype>
#include <cstdio>
#include <sstream>

namespace customers::json {

namespace {

class Parser {
public:
  explicit Parser(const std::string &text) : s_(text) {}

  std::vector<Customer> document() {
    std::vector<Customer> out;
    expect('{');
    if (string() != "customers")
      fail("expected key \"customers\"");
    expect(':');
    expect('[');
    if (!peek(']')) {
      do
        out.push_back(customer());
      while (accept(','));
    }
    expect(']');
    expect('}');
    skip_ws();
    if (i_ != s_.size())
      fail("trailing data");
    return out;
  }

private:
  Customer customer() {
    Customer c;
    expect('{');
    if (!peek('}')) {
      do {
        const std::string key = string();
        expect(':');
        if (key == "id")
          c.id = integer();
        else if (key == "name")
          c.name = string();
        else if (key == "email")
          c.email = string();
        else if (key == "city")
          c.city = string();
        else
          fail("unknown key \"" + key + "\"");
      } while (accept(','));
    }
    expect('}');
    return c;
  }

  void skip_ws() {
    while (i_ < s_.size() && std::isspace(static_cast<unsigned char>(s_[i_])))
      ++i_;
  }
  bool peek(char c) {
    skip_ws();
    return i_ < s_.size() && s_[i_] == c;
  }
  bool accept(char c) {
    if (!peek(c))
      return false;
    ++i_;
    return true;
  }
  void expect(char c) {
    if (!accept(c))
      fail(std::string("expected '") + c + "'");
  }

  int integer() {
    skip_ws();
    const std::size_t start = i_;
    if (i_ < s_.size() && s_[i_] == '-')
      ++i_;
    while (i_ < s_.size() && std::isdigit(static_cast<unsigned char>(s_[i_])))
      ++i_;
    if (start == i_)
      fail("expected a number");
    return std::stoi(s_.substr(start, i_ - start));
  }

  std::string string() {
    expect('"');
    std::string out;
    while (i_ < s_.size() && s_[i_] != '"') {
      const char c = s_[i_++];
      if (c != '\\') {
        out += c;
        continue;
      }
      if (i_ >= s_.size())
        break;
      switch (const char e = s_[i_++]) {
      case 'n': out += '\n'; break;
      case 't': out += '\t'; break;
      case 'r': out += '\r'; break;
      case 'u': // \u00XX only (what serialize writes)
        out += static_cast<char>(std::stoi(s_.substr(i_, 4), nullptr, 16));
        i_ += 4;
        break;
      default: out += e; // \" \\ \/
      }
    }
    expect('"');
    return out;
  }

  [[noreturn]] void fail(const std::string &what) const {
    throw ParseError(what + " at offset " + std::to_string(i_));
  }

  const std::string &s_;
  std::size_t i_ = 0;
};

} // namespace

std::vector<Customer> parse(const std::string &text) { return Parser(text).document(); }

std::string quote(const std::string &s) {
  std::string out = "\"";
  for (const char c : s) {
    switch (c) {
    case '"': out += "\\\""; break;
    case '\\': out += "\\\\"; break;
    case '\n': out += "\\n"; break;
    case '\t': out += "\\t"; break;
    case '\r': out += "\\r"; break;
    default:
      if (static_cast<unsigned char>(c) < 0x20) {
        char buf[7];
        std::snprintf(buf, sizeof buf, "\\u%04x", c);
        out += buf;
      } else {
        out += c;
      }
    }
  }
  return out + '"';
}

std::string serialize(const std::vector<Customer> &list) {
  std::ostringstream out;
  out << "{\n  \"customers\": [";
  for (std::size_t i = 0; i < list.size(); ++i) {
    const Customer &c = list[i];
    out << (i ? ",\n" : "\n") << "    {\"id\": " << c.id << ", \"name\": " << quote(c.name)
        << ", \"email\": " << quote(c.email) << ", \"city\": " << quote(c.city) << "}";
  }
  out << (list.empty() ? "]\n}\n" : "\n  ]\n}\n");
  return out.str();
}

} // namespace customers::json
