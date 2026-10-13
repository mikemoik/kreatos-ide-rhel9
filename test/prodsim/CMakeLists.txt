# prodsim: a stand-in for the prod software, using every dist/ package plus
# the RHEL graphics libraries. Built in the kide container against
# /workspace/ibn-dist (build-dist.sh), installed to /workspace, run on the
# host.
# See README.md.
cmake_minimum_required(VERSION 3.23)
project(prodsim LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

# installed binaries and libraries find each other (PREFIX/lib) and the dist/
# libraries (PREFIX/ibn-dist/lib, lib64) relative to themselves, wherever
# the host has ~/workspace
set(CMAKE_INSTALL_RPATH "$ORIGIN/../lib;$ORIGIN/../ibn-dist/lib;$ORIGIN/../ibn-dist/lib64")

find_package(OpenDDS REQUIRED)       # also ACE/TAO (TAO::*), tao_idl, opendds_idl
find_package(onnxruntime REQUIRED)
find_package(GDAL REQUIRED)          # the dist's GDAL (with GTiff), not RHEL's
find_package(glfw3 REQUIRED)
find_package(GLEW REQUIRED)
set(OpenGL_GL_PREFERENCE GLVND)
find_package(OpenGL REQUIRED)
find_path(RAPIDJSON_INCLUDE_DIR rapidjson/document.h REQUIRED) # headers from build-dist.sh

# --- prodsim-idlc: own IDL compiler on TAO's front end, linked like prod ------
# Prod style on purpose: plain library names (ACE, TAO_IDL_FE) and TAO_IDL's
# headers from TAO_ROOT, no imported targets. That needs TAO_ROOT
# (PREFIX/share/tao), and the ACE headers and libraries from the environment
# (CPLUS_INCLUDE_PATH, LIBRARY_PATH): all from ibn-dist-env.fish/.sh.
set(TAO_ROOT "$ENV{TAO_ROOT}" CACHE PATH "TAO_ROOT (PREFIX/share/tao)")
if(NOT EXISTS "${TAO_ROOT}/TAO_IDL/include/idl_defines.h")
  message(FATAL_ERROR "TAO_ROOT=${TAO_ROOT}: no TAO_IDL/include/idl_defines.h (build-dist.sh installs it)")
endif()
add_executable(prodsim-idlc
  idlc/idlc_main.cpp idlc/drv_args.cpp idlc/drv_preproc.cpp idlc/be_produce.cpp)
# idlc/ first: its be_global.h/be_extern.h/be_util.h replace TAO's backend
target_include_directories(prodsim-idlc PRIVATE idlc "${TAO_ROOT}/TAO_IDL/include")
target_link_libraries(prodsim-idlc PRIVATE ACE TAO_IDL_FE)

add_custom_command(
  OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/Track.schema.json ${CMAKE_CURRENT_BINARY_DIR}/Control.schema.json
  COMMAND prodsim-idlc -o ${CMAKE_CURRENT_BINARY_DIR}
          ${CMAKE_CURRENT_SOURCE_DIR}/idl/Track.idl ${CMAKE_CURRENT_SOURCE_DIR}/idl/Control.idl
  DEPENDS prodsim-idlc idl/Track.idl idl/Control.idl
  COMMENT "prodsim-idlc: IDL -> JSON schema")
add_custom_target(prodsim-schema ALL
  DEPENDS ${CMAKE_CURRENT_BINARY_DIR}/Track.schema.json ${CMAKE_CURRENT_BINARY_DIR}/Control.schema.json)

# --- IDL libraries ------------------------------------------------------------
# DDS topics: opendds_idl + tao_idl type support
add_library(prodsim_types SHARED)
opendds_target_sources(prodsim_types PUBLIC idl/Track.idl)
target_link_libraries(prodsim_types PUBLIC OpenDDS::Dcps)

# CORBA interface: tao_idl stubs and skeletons, no DDS
add_library(prodsim_control SHARED)
opendds_target_sources(prodsim_control PUBLIC idl/Control.idl
  SKIP_OPENDDS_IDL GENERATE_SERVER_SKELETONS TRUE SUPPRESS_ANYS FALSE)
target_link_libraries(prodsim_control PUBLIC TAO::PortableServer TAO::AnyTypeCode)

add_library(prodsim_common SHARED src/common.cpp)
target_link_libraries(prodsim_common PUBLIC
  prodsim_types prodsim_control OpenDDS::Dcps OpenDDS::Rtps OpenDDS::Rtps_Udp)

# --- programs -------------------------------------------------------------------
add_executable(prodsim-control src/control.cpp)
target_link_libraries(prodsim-control PRIVATE prodsim_common)

add_executable(prodsim-sensor src/sensor.cpp src/ort_model.cpp)
target_link_libraries(prodsim-sensor PRIVATE prodsim_common onnxruntime::onnxruntime GDAL::GDAL)

add_executable(prodsim-tracker src/tracker.cpp)
target_include_directories(prodsim-tracker PRIVATE ${RAPIDJSON_INCLUDE_DIR})
target_link_libraries(prodsim-tracker PRIVATE prodsim_common)

add_executable(prodsim-viewer src/viewer.cpp)
target_link_libraries(prodsim-viewer PRIVATE prodsim_common glfw GLEW::GLEW OpenGL::GL)

# --- install into CMAKE_INSTALL_PREFIX (/workspace) ---------------------------
install(TARGETS prodsim-idlc prodsim-control prodsim-sensor prodsim-tracker prodsim-viewer
  RUNTIME DESTINATION bin)
install(TARGETS prodsim_types prodsim_control prodsim_common LIBRARY DESTINATION lib)
install(PROGRAMS prodsim-demo DESTINATION bin)
install(FILES rtps.ini data/tile_sigmoid.onnx
  ${CMAKE_CURRENT_BINARY_DIR}/Track.schema.json ${CMAKE_CURRENT_BINARY_DIR}/Control.schema.json
  DESTINATION share/prodsim)
