# Included by the supported Flutter desktop projects.
find_program(CARGO_EXECUTABLE cargo)
if(NOT CARGO_EXECUTABLE)
  message(FATAL_ERROR "Rust stable is required: install cargo and the platform target with rustup")
endif()
get_filename_component(SKYPORT_WORKSPACE "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)
set(SKYPORT_RUST_TARGET_DIR "${CMAKE_BINARY_DIR}/rust")

if(WIN32)
  if(CMAKE_GENERATOR_PLATFORM MATCHES "[Aa][Rr][Mm]64" OR CMAKE_SYSTEM_PROCESSOR MATCHES "^(ARM64|aarch64)$")
    set(SKYPORT_RUST_TARGET "aarch64-pc-windows-msvc")
  else()
    set(SKYPORT_RUST_TARGET "x86_64-pc-windows-msvc")
  endif()
  set(SKYPORT_BRIDGE_NAME "skyport_flutter_bridge.dll")
else()
  if(CMAKE_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64)$")
    set(SKYPORT_RUST_TARGET "aarch64-unknown-linux-gnu")
  else()
    set(SKYPORT_RUST_TARGET "x86_64-unknown-linux-gnu")
  endif()
  set(SKYPORT_BRIDGE_NAME "libskyport_flutter_bridge.so")
endif()

set(SKYPORT_BRIDGE_LIBRARY "${SKYPORT_RUST_TARGET_DIR}/${SKYPORT_RUST_TARGET}/release/${SKYPORT_BRIDGE_NAME}")
# Cargo performs its own dependency tracking; invoking it also catches added Rust files.
add_custom_target(skyport_rust_bridge
  COMMAND "${CARGO_EXECUTABLE}" build --manifest-path "${SKYPORT_WORKSPACE}/Cargo.toml"
          --package skyport_flutter_bridge --release --locked
          --target "${SKYPORT_RUST_TARGET}" --target-dir "${SKYPORT_RUST_TARGET_DIR}"
  BYPRODUCTS "${SKYPORT_BRIDGE_LIBRARY}"
  WORKING_DIRECTORY "${SKYPORT_WORKSPACE}"
  VERBATIM
)
add_dependencies(${BINARY_NAME} skyport_rust_bridge)
install(FILES "${SKYPORT_BRIDGE_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}" COMPONENT Runtime)
