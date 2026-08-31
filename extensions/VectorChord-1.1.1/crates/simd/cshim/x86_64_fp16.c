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
#if !(__GNUC__ >= 12)
#error "GCC version must be at least 12."
#endif
#else
#error "This file requires Clang or GCC."
#endif

#include <immintrin.h>
#include <stddef.h>
#include <stdint.h>

#if defined(__clang__) && defined(_MSC_VER) && (__clang_major__ <= 19)
// https://github.com/llvm/llvm-project/issues/53520
// clang-format off
#include <pmmintrin.h>
#include <tmmintrin.h>
#include <smmintrin.h>
#include <lzcntintrin.h>
#include <avxintrin.h>
#include <avx2intrin.h>
#include <f16cintrin.h>
#include <fmaintrin.h>
#include <bmiintrin.h>
#include <bmi2intrin.h>
#include <lzcntintrin.h>
#include <avx512fintrin.h>
#include <avx512bwintrin.h>
#include <avx512cdintrin.h>
#include <avx512dqintrin.h>
#include <avx512vlintrin.h>
#include <avx512vlbwintrin.h>
#include <avx512vlcdintrin.h>
#include <avx512vldqintrin.h>
#include <avx512fp16intrin.h>
#include <avx512vlfp16intrin.h>
// clang-format on
#endif

typedef _Float16 f16;
typedef float f32;

__attribute__((target("avx512bw,avx512cd,avx512dq,avx512vl,bmi,bmi2,lzcnt,"
                      "movbe,popcnt,avx512fp16"))) float
fp16_reduce_sum_of_xy_v4_avx512fp16(size_t n, f16 *restrict a,
                                    f16 *restrict b) {
  __m512h _0 = _mm512_setzero_ph();
  __m512h _1 = _mm512_setzero_ph();
  while (n >= 64) {
    __m512h x_0 = _mm512_loadu_ph(a + 0);
    __m512h x_1 = _mm512_loadu_ph(a + 32);
    __m512h y_0 = _mm512_loadu_ph(b + 0);
    __m512h y_1 = _mm512_loadu_ph(b + 32);
    _0 = _mm512_fmadd_ph(x_0, y_0, _0);
    _1 = _mm512_fmadd_ph(x_1, y_1, _1);
    n -= 64, a += 64, b += 64;
  }
  while (n >= 32) {
    __m512h x_0 = _mm512_loadu_ph(a + 0);
    __m512h y_0 = _mm512_loadu_ph(b + 0);
    _0 = _mm512_fmadd_ph(x_0, y_0, _0);
    n -= 32, a += 32, b += 32;
  }
  if (n > 0) {
    unsigned int mask = _bzhi_u32(0xffffffff, n);
    __m512h x = _mm512_castsi512_ph(_mm512_maskz_loadu_epi16(mask, a));
    __m512h y = _mm512_castsi512_ph(_mm512_maskz_loadu_epi16(mask, b));
    _1 = _mm512_fmadd_ph(x, y, _1);
  }
  __m512 s_0 =
      _mm512_cvtph_ps(_mm512_extracti64x4_epi64(_mm512_castph_si512(_0), 0));
  __m512 s_1 =
      _mm512_cvtph_ps(_mm512_extracti64x4_epi64(_mm512_castph_si512(_0), 1));
  __m512 s_2 =
      _mm512_cvtph_ps(_mm512_extracti64x4_epi64(_mm512_castph_si512(_1), 0));
  __m512 s_3 =
      _mm512_cvtph_ps(_mm512_extracti64x4_epi64(_mm512_castph_si512(_1), 1));
  return _mm512_reduce_add_ps(
      _mm512_add_ps(_mm512_add_ps(s_0, s_2), _mm512_add_ps(s_1, s_3)));
}

__attribute__((target("avx512bw,avx512cd,avx512dq,avx512vl,bmi,bmi2,lzcnt,"
                      "movbe,popcnt,avx512fp16"))) float
fp16_reduce_sum_of_d2_v4_avx512fp16(size_t n, f16 *restrict a,
                                    f16 *restrict b) {
  __m512h _0 = _mm512_setzero_ph();
  __m512h _1 = _mm512_setzero_ph();
  while (n >= 64) {
    __m512h x_0 = _mm512_loadu_ph(a + 0);
    __m512h x_1 = _mm512_loadu_ph(a + 32);
    __m512h y_0 = _mm512_loadu_ph(b + 0);
    __m512h y_1 = _mm512_loadu_ph(b + 32);
    __m512h d_0 = _mm512_sub_ph(x_0, y_0);
    __m512h d_1 = _mm512_sub_ph(x_1, y_1);
    _0 = _mm512_fmadd_ph(d_0, d_0, _0);
    _1 = _mm512_fmadd_ph(d_1, d_1, _1);
    n -= 64, a += 64, b += 64;
  }
  while (n >= 32) {
    __m512h x_0 = _mm512_loadu_ph(a + 0);
    __m512h y_0 = _mm512_loadu_ph(b + 0);
    __m512h d_0 = _mm512_sub_ph(x_0, y_0);
    _0 = _mm512_fmadd_ph(d_0, d_0, _0);
    n -= 32, a += 32, b += 32;
  }
  if (n > 0) {
    unsigned int mask = _bzhi_u32(0xffffffff, n);
    __m512h x_1 = _mm512_castsi512_ph(_mm512_maskz_loadu_epi16(mask, a));
    __m512h y_1 = _mm512_castsi512_ph(_mm512_maskz_loadu_epi16(mask, b));
    __m512h d_1 = _mm512_sub_ph(x_1, y_1);
    _1 = _mm512_fmadd_ph(d_1, d_1, _1);
  }
  __m512 s_0 =
      _mm512_cvtph_ps(_mm512_extracti64x4_epi64(_mm512_castph_si512(_0), 0));
  __m512 s_1 =
      _mm512_cvtph_ps(_mm512_extracti64x4_epi64(_mm512_castph_si512(_0), 1));
  __m512 s_2 =
      _mm512_cvtph_ps(_mm512_extracti64x4_epi64(_mm512_castph_si512(_1), 0));
  __m512 s_3 =
      _mm512_cvtph_ps(_mm512_extracti64x4_epi64(_mm512_castph_si512(_1), 1));
  return _mm512_reduce_add_ps(
      _mm512_add_ps(_mm512_add_ps(s_0, s_2), _mm512_add_ps(s_1, s_3)));
}
