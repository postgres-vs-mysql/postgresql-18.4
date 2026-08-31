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
fp32_reduce_sum_of_xy_a3_256(size_t n, float *restrict lhs,
                             float *restrict rhs) {
  svfloat32_t sum = svdup_f32(0.0);
  for (size_t i = 0; i < n; i += svcntw()) {
    svbool_t mask = svwhilelt_b32((int64_t)i, (int64_t)n);
    svfloat32_t x = svld1_f32(mask, lhs + i);
    svfloat32_t y = svld1_f32(mask, rhs + i);
    sum = svmla_f32_m(mask, sum, x, y);
  }
  return svaddv_f32(svptrue_b32(), sum);
}

__attribute__((target("+sve"))) float
fp32_reduce_sum_of_d2_a3_256(size_t n, float *restrict lhs,
                             float *restrict rhs) {
  svfloat32_t sum = svdup_f32(0.0);
  for (size_t i = 0; i < n; i += svcntw()) {
    svbool_t mask = svwhilelt_b32((int64_t)i, (int64_t)n);
    svfloat32_t x = svld1_f32(mask, lhs + i);
    svfloat32_t y = svld1_f32(mask, rhs + i);
    svfloat32_t d = svsub_f32_z(mask, x, y);
    sum = svmla_f32_m(mask, sum, d, d);
  }
  return svaddv_f32(svptrue_b32(), sum);
}
