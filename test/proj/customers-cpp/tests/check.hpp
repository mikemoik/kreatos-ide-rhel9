// CHECK for plain CTest tests (no framework): exits non-zero on the first failure.
#pragma once

#include <cstdio>
#include <cstdlib>

#define CHECK(cond)                                                                                \
  do {                                                                                             \
    if (!(cond)) {                                                                                 \
      std::fprintf(stderr, "%s:%d: CHECK failed: %s\n", __FILE__, __LINE__, #cond);                \
      std::exit(1);                                                                                \
    }                                                                                              \
  } while (0)

/// CHECK that `expr` throws an exception of type `type`.
#define CHECK_THROWS(expr, type)                                                                   \
  do {                                                                                             \
    bool thrown_ = false;                                                                          \
    try {                                                                                          \
      (void)(expr);                                                                                \
    } catch (const type &) {                                                                       \
      thrown_ = true;                                                                              \
    }                                                                                              \
    CHECK(thrown_ && #expr " throws " #type);                                                      \
  } while (0)
