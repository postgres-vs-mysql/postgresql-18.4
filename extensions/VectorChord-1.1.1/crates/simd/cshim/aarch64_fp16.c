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

typedef __fp16 f16;
typedef float f32;

__attribute__((target("+fp16"))) float
fp16_reduce_sum_of_xy_a2_fp16(size_t n, f16 *restrict a, f16 *restrict b) {
  float16x8_t sum_0 = vdupq_n_f16(0.0);
  float16x8_t sum_1 = vdupq_n_f16(0.0);
  float16x8_t sum_2 = vdupq_n_f16(0.0);
  float16x8_t sum_3 = vdupq_n_f16(0.0);
  float16x8_t sum_4 = vdupq_n_f16(0.0);
  float16x8_t sum_5 = vdupq_n_f16(0.0);
  float16x8_t sum_6 = vdupq_n_f16(0.0);
  float16x8_t sum_7 = vdupq_n_f16(0.0);
  while (n >= 64) {
    float16x8_t x_0 = vld1q_f16(a + 0);
    float16x8_t x_1 = vld1q_f16(a + 8);
    float16x8_t x_2 = vld1q_f16(a + 16);
    float16x8_t x_3 = vld1q_f16(a + 24);
    float16x8_t x_4 = vld1q_f16(a + 32);
    float16x8_t x_5 = vld1q_f16(a + 40);
    float16x8_t x_6 = vld1q_f16(a + 48);
    float16x8_t x_7 = vld1q_f16(a + 56);
    float16x8_t y_0 = vld1q_f16(b + 0);
    float16x8_t y_1 = vld1q_f16(b + 8);
    float16x8_t y_2 = vld1q_f16(b + 16);
    float16x8_t y_3 = vld1q_f16(b + 24);
    float16x8_t y_4 = vld1q_f16(b + 32);
    float16x8_t y_5 = vld1q_f16(b + 40);
    float16x8_t y_6 = vld1q_f16(b + 48);
    float16x8_t y_7 = vld1q_f16(b + 56);
    sum_0 = vfmaq_f16(sum_0, x_0, y_0);
    sum_1 = vfmaq_f16(sum_1, x_1, y_1);
    sum_2 = vfmaq_f16(sum_2, x_2, y_2);
    sum_3 = vfmaq_f16(sum_3, x_3, y_3);
    sum_4 = vfmaq_f16(sum_4, x_4, y_4);
    sum_5 = vfmaq_f16(sum_5, x_5, y_5);
    sum_6 = vfmaq_f16(sum_6, x_6, y_6);
    sum_7 = vfmaq_f16(sum_7, x_7, y_7);
    n -= 64, a += 64, b += 64;
  }
  if (n >= 32) {
    float16x8_t x_0 = vld1q_f16(a + 0);
    float16x8_t x_1 = vld1q_f16(a + 8);
    float16x8_t x_2 = vld1q_f16(a + 16);
    float16x8_t x_3 = vld1q_f16(a + 24);
    float16x8_t y_0 = vld1q_f16(b + 0);
    float16x8_t y_1 = vld1q_f16(b + 8);
    float16x8_t y_2 = vld1q_f16(b + 16);
    float16x8_t y_3 = vld1q_f16(b + 24);
    sum_0 = vfmaq_f16(sum_0, x_0, y_0);
    sum_1 = vfmaq_f16(sum_1, x_1, y_1);
    sum_2 = vfmaq_f16(sum_2, x_2, y_2);
    sum_3 = vfmaq_f16(sum_3, x_3, y_3);
    n -= 32, a += 32, b += 32;
  }
  if (n >= 16) {
    float16x8_t x_4 = vld1q_f16(a + 0);
    float16x8_t x_5 = vld1q_f16(a + 8);
    float16x8_t y_4 = vld1q_f16(b + 0);
    float16x8_t y_5 = vld1q_f16(b + 8);
    sum_4 = vfmaq_f16(sum_4, x_4, y_4);
    sum_5 = vfmaq_f16(sum_5, x_5, y_5);
    n -= 16, a += 16, b += 16;
  }
  if (n >= 8) {
    float16x8_t x_6 = vld1q_f16(a + 0);
    float16x8_t y_6 = vld1q_f16(b + 0);
    sum_6 = vfmaq_f16(sum_6, x_6, y_6);
    n -= 8, a += 8, b += 8;
  }
  if (n > 0) {
    f16 _a[8] = {}, _b[8] = {};
    for (size_t i = 0; i < n; i += 1) {
      _a[i] = a[i], _b[i] = b[i];
    }
    a = _a, b = _b;
    float16x8_t x_7 = vld1q_f16(a);
    float16x8_t y_7 = vld1q_f16(b);
    sum_7 = vfmaq_f16(sum_7, x_7, y_7);
  }
  float32x4_t s_0 = vcvt_f32_f16(vget_low_f16(sum_0));
  float32x4_t s_1 = vcvt_f32_f16(vget_high_f16(sum_0));
  float32x4_t s_2 = vcvt_f32_f16(vget_low_f16(sum_1));
  float32x4_t s_3 = vcvt_f32_f16(vget_high_f16(sum_1));
  float32x4_t s_4 = vcvt_f32_f16(vget_low_f16(sum_2));
  float32x4_t s_5 = vcvt_f32_f16(vget_high_f16(sum_2));
  float32x4_t s_6 = vcvt_f32_f16(vget_low_f16(sum_3));
  float32x4_t s_7 = vcvt_f32_f16(vget_high_f16(sum_3));
  float32x4_t s_8 = vcvt_f32_f16(vget_low_f16(sum_4));
  float32x4_t s_9 = vcvt_f32_f16(vget_high_f16(sum_4));
  float32x4_t s_a = vcvt_f32_f16(vget_low_f16(sum_5));
  float32x4_t s_b = vcvt_f32_f16(vget_high_f16(sum_5));
  float32x4_t s_c = vcvt_f32_f16(vget_low_f16(sum_6));
  float32x4_t s_d = vcvt_f32_f16(vget_high_f16(sum_6));
  float32x4_t s_e = vcvt_f32_f16(vget_low_f16(sum_7));
  float32x4_t s_f = vcvt_f32_f16(vget_high_f16(sum_7));
  float32x4_t s = vpaddq_f32(
      vpaddq_f32(vpaddq_f32(vpaddq_f32(s_0, s_1), vpaddq_f32(s_2, s_3)),
                 vpaddq_f32(vpaddq_f32(s_4, s_5), vpaddq_f32(s_6, s_7))),
      vpaddq_f32(vpaddq_f32(vpaddq_f32(s_8, s_9), vpaddq_f32(s_a, s_b)),
                 vpaddq_f32(vpaddq_f32(s_c, s_d), vpaddq_f32(s_e, s_f))));
  return vaddvq_f32(s);
}

__attribute__((target("+fp16"))) float
fp16_reduce_sum_of_d2_a2_fp16(size_t n, f16 *restrict a, f16 *restrict b) {
  float16x8_t sum_0 = vdupq_n_f16(0.0);
  float16x8_t sum_1 = vdupq_n_f16(0.0);
  float16x8_t sum_2 = vdupq_n_f16(0.0);
  float16x8_t sum_3 = vdupq_n_f16(0.0);
  float16x8_t sum_4 = vdupq_n_f16(0.0);
  float16x8_t sum_5 = vdupq_n_f16(0.0);
  float16x8_t sum_6 = vdupq_n_f16(0.0);
  float16x8_t sum_7 = vdupq_n_f16(0.0);
  while (n >= 64) {
    float16x8_t x_0 = vld1q_f16(a + 0);
    float16x8_t x_1 = vld1q_f16(a + 8);
    float16x8_t x_2 = vld1q_f16(a + 16);
    float16x8_t x_3 = vld1q_f16(a + 24);
    float16x8_t x_4 = vld1q_f16(a + 32);
    float16x8_t x_5 = vld1q_f16(a + 40);
    float16x8_t x_6 = vld1q_f16(a + 48);
    float16x8_t x_7 = vld1q_f16(a + 56);
    float16x8_t y_0 = vld1q_f16(b + 0);
    float16x8_t y_1 = vld1q_f16(b + 8);
    float16x8_t y_2 = vld1q_f16(b + 16);
    float16x8_t y_3 = vld1q_f16(b + 24);
    float16x8_t y_4 = vld1q_f16(b + 32);
    float16x8_t y_5 = vld1q_f16(b + 40);
    float16x8_t y_6 = vld1q_f16(b + 48);
    float16x8_t y_7 = vld1q_f16(b + 56);
    float16x8_t d_0 = vsubq_f16(x_0, y_0);
    float16x8_t d_1 = vsubq_f16(x_1, y_1);
    float16x8_t d_2 = vsubq_f16(x_2, y_2);
    float16x8_t d_3 = vsubq_f16(x_3, y_3);
    float16x8_t d_4 = vsubq_f16(x_4, y_4);
    float16x8_t d_5 = vsubq_f16(x_5, y_5);
    float16x8_t d_6 = vsubq_f16(x_6, y_6);
    float16x8_t d_7 = vsubq_f16(x_7, y_7);
    sum_0 = vfmaq_f16(sum_0, d_0, d_0);
    sum_1 = vfmaq_f16(sum_1, d_1, d_1);
    sum_2 = vfmaq_f16(sum_2, d_2, d_2);
    sum_3 = vfmaq_f16(sum_3, d_3, d_3);
    sum_4 = vfmaq_f16(sum_4, d_4, d_4);
    sum_5 = vfmaq_f16(sum_5, d_5, d_5);
    sum_6 = vfmaq_f16(sum_6, d_6, d_6);
    sum_7 = vfmaq_f16(sum_7, d_7, d_7);
    n -= 64, a += 64, b += 64;
  }
  if (n >= 32) {
    float16x8_t x_0 = vld1q_f16(a + 0);
    float16x8_t x_1 = vld1q_f16(a + 8);
    float16x8_t x_2 = vld1q_f16(a + 16);
    float16x8_t x_3 = vld1q_f16(a + 24);
    float16x8_t y_0 = vld1q_f16(b + 0);
    float16x8_t y_1 = vld1q_f16(b + 8);
    float16x8_t y_2 = vld1q_f16(b + 16);
    float16x8_t y_3 = vld1q_f16(b + 24);
    float16x8_t d_0 = vsubq_f16(x_0, y_0);
    float16x8_t d_1 = vsubq_f16(x_1, y_1);
    float16x8_t d_2 = vsubq_f16(x_2, y_2);
    float16x8_t d_3 = vsubq_f16(x_3, y_3);
    sum_0 = vfmaq_f16(sum_0, d_0, d_0);
    sum_1 = vfmaq_f16(sum_1, d_1, d_1);
    sum_2 = vfmaq_f16(sum_2, d_2, d_2);
    sum_3 = vfmaq_f16(sum_3, d_3, d_3);
    n -= 32, a += 32, b += 32;
  }
  if (n >= 16) {
    float16x8_t x_4 = vld1q_f16(a + 0);
    float16x8_t x_5 = vld1q_f16(a + 8);
    float16x8_t y_4 = vld1q_f16(b + 0);
    float16x8_t y_5 = vld1q_f16(b + 8);
    float16x8_t d_4 = vsubq_f16(x_4, y_4);
    float16x8_t d_5 = vsubq_f16(x_5, y_5);
    sum_4 = vfmaq_f16(sum_4, d_4, d_4);
    sum_5 = vfmaq_f16(sum_5, d_5, d_5);
    n -= 16, a += 16, b += 16;
  }
  if (n >= 8) {
    float16x8_t x_6 = vld1q_f16(a + 0);
    float16x8_t y_6 = vld1q_f16(b + 0);
    float16x8_t d_6 = vsubq_f16(x_6, y_6);
    sum_6 = vfmaq_f16(sum_6, d_6, d_6);
    n -= 8, a += 8, b += 8;
  }
  if (n > 0) {
    f16 _a[8] = {}, _b[8] = {};
    for (size_t i = 0; i < n; i += 1) {
      _a[i] = a[i], _b[i] = b[i];
    }
    a = _a, b = _b;
    float16x8_t x_7 = vld1q_f16(a);
    float16x8_t y_7 = vld1q_f16(b);
    float16x8_t d_7 = vsubq_f16(x_7, y_7);
    sum_7 = vfmaq_f16(sum_7, d_7, d_7);
  }
  float32x4_t s_0 = vcvt_f32_f16(vget_low_f16(sum_0));
  float32x4_t s_1 = vcvt_f32_f16(vget_high_f16(sum_0));
  float32x4_t s_2 = vcvt_f32_f16(vget_low_f16(sum_1));
  float32x4_t s_3 = vcvt_f32_f16(vget_high_f16(sum_1));
  float32x4_t s_4 = vcvt_f32_f16(vget_low_f16(sum_2));
  float32x4_t s_5 = vcvt_f32_f16(vget_high_f16(sum_2));
  float32x4_t s_6 = vcvt_f32_f16(vget_low_f16(sum_3));
  float32x4_t s_7 = vcvt_f32_f16(vget_high_f16(sum_3));
  float32x4_t s_8 = vcvt_f32_f16(vget_low_f16(sum_4));
  float32x4_t s_9 = vcvt_f32_f16(vget_high_f16(sum_4));
  float32x4_t s_a = vcvt_f32_f16(vget_low_f16(sum_5));
  float32x4_t s_b = vcvt_f32_f16(vget_high_f16(sum_5));
  float32x4_t s_c = vcvt_f32_f16(vget_low_f16(sum_6));
  float32x4_t s_d = vcvt_f32_f16(vget_high_f16(sum_6));
  float32x4_t s_e = vcvt_f32_f16(vget_low_f16(sum_7));
  float32x4_t s_f = vcvt_f32_f16(vget_high_f16(sum_7));
  float32x4_t s = vpaddq_f32(
      vpaddq_f32(vpaddq_f32(vpaddq_f32(s_0, s_1), vpaddq_f32(s_2, s_3)),
                 vpaddq_f32(vpaddq_f32(s_4, s_5), vpaddq_f32(s_6, s_7))),
      vpaddq_f32(vpaddq_f32(vpaddq_f32(s_8, s_9), vpaddq_f32(s_a, s_b)),
                 vpaddq_f32(vpaddq_f32(s_c, s_d), vpaddq_f32(s_e, s_f))));
  return vaddvq_f32(s);
}
