# test/run.sh: onnxruntime and OpenDDS (+ ACE/TAO, IDL code generation) from
# the kide prefix, found by the bundled cmake without any hints
cmake_minimum_required(VERSION 3.23)
project(devlibs LANGUAGES CXX)

find_package(onnxruntime REQUIRED)
find_package(OpenDDS REQUIRED)

add_executable(devlibs main.cpp)
opendds_target_sources(devlibs Msg.idl)
target_link_libraries(devlibs onnxruntime::onnxruntime OpenDDS::Dcps)
