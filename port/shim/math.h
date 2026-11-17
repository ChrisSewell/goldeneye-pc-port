/*
 * PC port shim for <math.h>.
 *
 * C game code gets the N64 include/math.h, as before. The iOS build's C++
 * TUs (fast3d, Apple clang + libc++) reach this file from libc++'s own
 * <math.h> wrapper (#include_next), and must get the HOST header there, or
 * <cmath> finds no fabsf/isinf. The generated hostmath.h (CMake, iOS only)
 * includes it by absolute path, the same trick as port/shim/string.h.
 *
 * Inert in the N64 build (port/shim is not on its include path).
 */
#if defined(__cplusplus) && __has_include("hostmath.h")
#include "hostmath.h"
#else
#include "include/math.h"
#endif
