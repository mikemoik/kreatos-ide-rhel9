cmake_minimum_required(VERSION 3.20)
project(customers LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON) # for clangd

add_subdirectory(src)   # library customers::db
add_subdirectory(app)   # executable customers

enable_testing()
add_subdirectory(tests)
