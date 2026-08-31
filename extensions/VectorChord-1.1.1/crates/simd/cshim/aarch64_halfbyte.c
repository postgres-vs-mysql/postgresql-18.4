// This software is licensed under a dual license model:
//
// GNU Affero General Public License v3 (AGPLv3): You may use, modify, and
// distribute this software under the terms of the AGPLv3.
//
// Elastic License v2 (ELv2): You may also use, modify, and distribute this
// software under the Elastic License v2, which has specific restrictions.
//
// We welcome any commercial collaboration or support. For inquiries
// regarding the licenses, please contact us at:
// vectorchord-inquiry@tensorchord.ai
//
// Copyright (c) 2025 TensorChord Inc.

#if defined(__clang__)
#if !(__clang_major__ >= 16)
#error "Clang version must be at least 16."
#endif
#elif defined(__GNUC__)
#if !(__GNUC__ >= 14)
#error "GCC version must be at least 14."
#endif
#else
#error "This file requires Clang or GCC."
#endif

#include <arm_neon.h>
#include <stddef.h>
#include <stdint.h>

__attribute__((target("+dotprod"))) uint32_t
halfbyte_reduce_sum_of_xy_a2_dotprod(size_t n, uint8_t *restrict a,
                                     uint8_t *restrict b) {
  uint8x16_t lo = vdupq_n_u8(0x0f);
  uint32x4_t _0 = vdupq_n_u32(0);
  uint32x4_t _1 = vdupq_n_u32(0);
  while (n >= 16) {
    uint8x16_t x = vld1q_u8(a);
    uint8x16_t y = vld1q_u8(b);
    uint8x16_t x_0 = vandq_u8(x, lo);
    uint8x16_t x_1 = vshrq_n_u8(x, 4);
    uint8x16_t y_0 = vandq_u8(y, lo);
    uint8x16_t y_1 = vshrq_n_u8(y, 4);
    _0 = vdotq_u32(_0, x_0, y_0);
    _1 = vdotq_u32(_1, x_1, y_1);
    n -= 16, a += 16, b += 16;
  }
  if (n > 0) {
    uint8_t _a[16] = {}, _b[16] = {};
    for (size_t i = 0; i < n; i += 1) {
      _a[i] = a[i], _b[i] = b[i];
    }
    a = _a, b = _b;
    uint8x16_t x = vld1q_u8(a);
    uint8x16_t y = vld1q_u8(b);
    uint8x16_t x_0 = vandq_u8(x, lo);
    uint8x16_t x_1 = vshrq_n_u8(x, 4);
    uint8x16_t y_0 = vandq_u8(y, lo);
    uint8x16_t y_1 = vshrq_n_u8(y, 4);
    _0 = vdotq_u32(_0, x_0, y_0);
    _1 = vdotq_u32(_1, x_1, y_1);
  }
  return vaddvq_u32(vaddq_u32(_0, _1));
}
