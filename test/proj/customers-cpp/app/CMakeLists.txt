add_executable(customers main.cpp cli.cpp)
target_link_libraries(customers PRIVATE customers::db)
target_compile_options(customers PRIVATE -Wall -Wextra)
