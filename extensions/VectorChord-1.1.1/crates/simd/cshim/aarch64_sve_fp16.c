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
#if defined(__AARCH64EL__)
#include <arm_sve.h>
#endif
#include <stddef.h>
#include <stdint.h>

typedef __fp16 f16;
typedef float f32;

__attribute__((target("+sve"))) float
fp16_reduce_sum_of_xy_a3_512(size_t n, f16 *restrict a, f16 *restrict b) {
  const size_t vl = svcnth();
  svfloat16_t _0 = svdup_f16(0.0);
  svfloat16_t _1 = svdup_f16(0.0);
  while (n >= vl * 2) {
    svbool_t mask = svptrue_b16();
    svfloat16_t x_0 = svld1_f16(mask, a + 0 * vl);
    svfloat16_t y_0 = svld1_f16(mask, b + 0 * vl);
    svfloat16_t x_1 = svld1_f16(mask, a + 1 * vl);
    svfloat16_t y_1 = svld1_f16(mask, b + 1 * vl);
    _0 = svmla_f16_x(mask, _0, x_0, y_0);
    _1 = svmla_f16_x(mask, _1, x_1, y_1);
    n -= vl * 2, a += vl * 2, b += vl * 2;
  }
  if (n >= vl) {
    svbool_t mask = svptrue_b16();
    svfloat16_t x_0 = svld1_f16(mask, a + 0 * vl);
    svfloat16_t y_0 = svld1_f16(mask, b + 0 * vl);
    _0 = svmla_f16_x(mask, _0, x_0, y_0);
    n -= vl * 1, a += vl * 1, b += vl * 1;
  }
  if (n > 0) {
    svbool_t mask = svwhilelt_b16((int64_t)0, (int64_t)n);
    svfloat16_t x_0 = svld1_f16(mask, a);
    svfloat16_t y_0 = svld1_f16(mask, b);
    _0 = svmla_f16_m(mask, _0, x_0, y_0);
  }
  svbool_t mask = svptrue_b32();
  svfloat32_t s_0 = svcvt_f32_f16_x(mask, _0);
  svfloat32_t s_1 = svcvt_f32_f16_x(mask, svext_f16(_0, _0, 1));
  svfloat32_t s_2 = svcvt_f32_f16_x(mask, _1);
  svfloat32_t s_3 = svcvt_f32_f16_x(mask, svext_f16(_1, _1, 1));
  return svaddv_f32(mask, svadd_f32_x(mask, svadd_f32_x(mask, s_0, s_2),
                                      svadd_f32_x(mask, s_1, s_3)));
}

__attribute__((target("+sve"))) float
fp16_reduce_sum_of_d2_a3_512(size_t n, f16 *restrict a, f16 *restrict b) {
  const size_t vl = svcnth();
  svfloat16_t _0 = svdup_f16(0.0);
  svfloat16_t _1 = svdup_f16(0.0);
  while (n >= vl * 2) {
    svbool_t mask = svptrue_b16();
    svfloat16_t x_0 = svld1_f16(mask, a + 0 * vl);
    svfloat16_t y_0 = svld1_f16(mask, b + 0 * vl);
    svfloat16_t x_1 = svld1_f16(mask, a + 1 * vl);
    svfloat16_t y_1 = svld1_f16(mask, b + 1 * vl);
    svfloat16_t d_0 = svsub_f16_z(mask, x_0, y_0);
    svfloat16_t d_1 = svsub_f16_z(mask, x_1, y_1);
    _0 = svmla_f16_x(mask, _0, d_0, d_0);
    _1 = svmla_f16_x(mask, _1, d_1, d_1);
    n -= vl * 2, a += vl * 2, b += vl * 2;
  }
  if (n >= vl) {
    svbool_t mask = svptrue_b16();
    svfloat16_t x_0 = svld1_f16(mask, a + 0 * vl);
    svfloat16_t y_0 = svld1_f16(mask, b + 0 * vl);
    svfloat16_t d_0 = svsub_f16_z(mask, x_0, y_0);
    _0 = svmla_f16_x(mask, _0, d_0, d_0);
    n -= vl * 1, a += vl * 1, b += vl * 1;
  }
  if (n > 0) {
    svbool_t mask = svwhilelt_b16((int64_t)0, (int64_t)n);
    svfloat16_t x_0 = svld1_f16(mask, a);
    svfloat16_t y_0 = svld1_f16(mask, b);
    svfloat16_t d_0 = svsub_f16_z(mask, x_0, y_0);
    _0 = svmla_f16_m(mask, _0, d_0, d_0);
  }
  svbool_t mask = svptrue_b32();
  svfloat32_t s_0 = svcvt_f32_f16_x(mask, _0);
  svfloat32_t s_1 = svcvt_f32_f16_x(mask, svext_f16(_0, _0, 1));
  svfloat32_t s_2 = svcvt_f32_f16_x(mask, _1);
  svfloat32_t s_3 = svcvt_f32_f16_x(mask, svext_f16(_1, _1, 1));
  return svaddv_f32(mask, svadd_f32_x(mask, svadd_f32_x(mask, s_0, s_2),
                                      svadd_f32_x(mask, s_1, s_3)));
}
