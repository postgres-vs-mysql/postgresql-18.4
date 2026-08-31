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
use trace::{trace_guard, trace_vchord_print};
const BITS: &[u8; 262144] = include_bytes!(concat!(env!("OUT_DIR"), "/bits"));

#[cfg(target_endian = "little")]
const _: () = {
    assert!(BITS[0] == 246);
    assert!(BITS[1] == 133);
    assert!(BITS[2] == 163);
    assert!(BITS[3] == 106);
    assert!(BITS[4] == 54);
    assert!(BITS[5] == 126);
    assert!(BITS[6] == 9);
    assert!(BITS[7] == 115);
};

#[cfg(target_endian = "big")]
const _: () = {
    assert!(BITS[7] == 246);
    assert!(BITS[6] == 133);
    assert!(BITS[5] == 163);
    assert!(BITS[4] == 106);
    assert!(BITS[3] == 54);
    assert!(BITS[2] == 126);
    assert!(BITS[1] == 9);
    assert!(BITS[0] == 115);
};

static BITS_0: [u64; 1024] = zerocopy::transmute!(BITS.as_chunks::<8192>().0[0]);
static BITS_1: [u64; 1024] = zerocopy::transmute!(BITS.as_chunks::<8192>().0[1]);
static BITS_2: [u64; 1024] = zerocopy::transmute!(BITS.as_chunks::<8192>().0[2]);
static BITS_3: [u64; 1024] = zerocopy::transmute!(BITS.as_chunks::<8192>().0[3]);

fn kacs_walk(result: &mut [f32]) {
    let _guard = trace_guard!("kacs_walk [rust]");
    let n = result.len();
    let m = n / 2;
    let (l, t) = result.split_at_mut(m);
    let (_, r) = t.split_at_mut(n - 2 * m);
    let l_sum: f32 = l.iter().sum();
    let r_sum: f32 = r.iter().sum();
    simd::rotate::givens(l, r);
    let l_sum_after: f32 = l.iter().sum();
    let r_sum_after: f32 = r.iter().sum();
    trace_vchord_print!(
        "givens rotation: n={}, m={}, l_len={}, r_len={}",
        n,
        m,
        l.len(),
        r.len()
    );
    trace_vchord_print!("l_sum: {}, r_sum: {}", l_sum, r_sum);
    trace_vchord_print!("after - l_sum: {}, r_sum: {}", l_sum_after, r_sum_after);
}

pub fn rotate(vector: &[f32]) -> Vec<f32> {
    let _guard = trace_guard!("rabitq::rotate [rust]");
    let mut vector = vector.to_vec();
    rotate_inplace(&mut vector);
    vector
}

pub fn rotate_inplace(result: &mut [f32]) {
    let _guard = trace_guard!("rotate_inplace [rust]");
    use simd::Floating;
    use std::ops::Bound::{Excluded, Included, Unbounded};

    let n = result.len();
    let base = n.ilog2();
    let scale = 1.0 / ((1_usize << base) as f32).sqrt();

    let l = (Unbounded, Excluded(1_usize << base));
    let r = (Included(n - (1_usize << base)), Unbounded);

    simd::rotate::flip(&BITS_0, result);
    simd::fht::fht(&mut result[l]);
    f32::vector_mul_scalar_inplace(&mut result[l], scale);
    if n != (1_usize << base) {
        kacs_walk(result);
    }

    simd::rotate::flip(&BITS_1, result);
    simd::fht::fht(&mut result[r]);
    f32::vector_mul_scalar_inplace(&mut result[r], scale);
    if n != (1_usize << base) {
        kacs_walk(result);
    }

    simd::rotate::flip(&BITS_2, result);
    simd::fht::fht(&mut result[l]);
    f32::vector_mul_scalar_inplace(&mut result[l], scale);
    if n != (1_usize << base) {
        kacs_walk(result);
    }

    simd::rotate::flip(&BITS_3, result);
    simd::fht::fht(&mut result[r]);
    f32::vector_mul_scalar_inplace(&mut result[r], scale);
    if n != (1_usize << base) {
        kacs_walk(result);
    }
}

pub fn rotate_reversed_inplace(result: &mut [f32]) {
    let _guard = trace_guard!("rotate_reversed_inplace [rust]");
    use simd::Floating;
    use std::ops::Bound::{Excluded, Included, Unbounded};

    let n = result.len();
    let base = n.ilog2();
    let scale = 1.0 / ((1_usize << base) as f32).sqrt();

    let l = (Unbounded, Excluded(1_usize << base));
    let r = (Included(n - (1_usize << base)), Unbounded);

    if n != (1_usize << base) {
        kacs_walk(result);
    }
    f32::vector_mul_scalar_inplace(&mut result[r], scale);
    simd::fht::fht(&mut result[r]);
    simd::rotate::flip(&BITS_3, result);

    if n != (1_usize << base) {
        kacs_walk(result);
    }
    f32::vector_mul_scalar_inplace(&mut result[l], scale);
    simd::fht::fht(&mut result[l]);
    simd::rotate::flip(&BITS_2, result);

    if n != (1_usize << base) {
        kacs_walk(result);
    }
    f32::vector_mul_scalar_inplace(&mut result[r], scale);
    simd::fht::fht(&mut result[r]);
    simd::rotate::flip(&BITS_1, result);

    if n != (1_usize << base) {
        kacs_walk(result);
    }
    f32::vector_mul_scalar_inplace(&mut result[l], scale);
    simd::fht::fht(&mut result[l]);
    simd::rotate::flip(&BITS_0, result);
}

#[test]
fn reverse() {
    let mut x = vec![2.0, 3.0, 4.0];
    rotate_inplace(&mut x);
    assert!((x[0] - 3.981917).abs() < 1e-6);
    assert!((x[1] - 1.8043789).abs() < 1e-6);
    assert!((x[2] - 3.1446066).abs() < 1e-6);
    rotate_reversed_inplace(&mut x);
    assert!((x[0] - 2.0).abs() < 1e-6);
    assert!((x[1] - 3.0).abs() < 1e-6);
    assert!((x[2] - 4.0).abs() < 1e-6);
}
