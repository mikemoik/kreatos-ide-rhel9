# customers-cpp

Sample C++17/CMake project: a customer database stored in one JSON file
(`customers.json`), with a small built-in JSON reader/writer (no dependencies).

    include/customers/   public headers (customer, json, storage, customer_db, search, report)
    src/                 library customers::db
    app/                 the `customers` command line (cli.cpp, main.cpp)
    tests/               three CTest tests

Build, test, run:

    cmake -B build -DCMAKE_BUILD_TYPE=Debug
    cmake --build build
    ctest --test-dir build
    ./build/app/customers list
    ./build/app/customers report
    ./build/app/customers add "Alan Turing" alan@example.com Manchester
    ./build/app/customers update 4 city Wilmslow
    ./build/app/customers find ada
    ./build/app/customers delete 4

clangd finds `build/compile_commands.json` (CMAKE_EXPORT_COMPILE_COMMANDS);
in kide, cmake-tools does configure/build/debug from inside nvim.
