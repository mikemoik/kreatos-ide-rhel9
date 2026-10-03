#include "cli.hpp"

int main(int argc, char **argv) { return cli::run({argv + 1, argv + argc}); }
