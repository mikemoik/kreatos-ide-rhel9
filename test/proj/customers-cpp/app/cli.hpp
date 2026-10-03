// The `customers` command line.
#pragma once

#include <string>
#include <vector>

namespace cli {

/// Runs one command; returns the process exit code.
///   [--db FILE] {list | report | add NAME EMAIL [CITY] | get ID |
///                update ID name|email|city VALUE | delete ID | find TEXT}
int run(std::vector<std::string> args);

} // namespace cli
