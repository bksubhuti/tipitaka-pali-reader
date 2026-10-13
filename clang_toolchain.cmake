# Clang from the Freedesktop SDK's LLVM extension, for building inside the
# SDK (flatbuild.sh, and the Flathub step of build_linux.yml). Both set CC and
# CXX to that extension's clang, so the runtime version lives in one place.
set(CMAKE_C_COMPILER $ENV{CC} CACHE STRING "" FORCE)
set(CMAKE_CXX_COMPILER $ENV{CXX} CACHE STRING "" FORCE)
