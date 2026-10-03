add_library(customers_db
  customer.cpp
  customer_db.cpp
  json.cpp
  report.cpp
  search.cpp
  storage.cpp
)
add_library(customers::db ALIAS customers_db)
target_include_directories(customers_db PUBLIC ${PROJECT_SOURCE_DIR}/include)
target_compile_options(customers_db PRIVATE -Wall -Wextra)
