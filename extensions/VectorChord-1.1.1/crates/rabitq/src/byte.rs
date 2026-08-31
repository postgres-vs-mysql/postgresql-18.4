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

pub use crate::extended::{Code, CodeMetadata};
use trace::trace_guard;

#[deprecated]
pub fn code(vector: &[f32]) -> Code {
    let _guard = trace_guard!("byte::code [rust]");
    crate::extended::code::<8>(vector)
}

pub fn ugly_code(vector: &[f32]) -> Code {
    let _guard = trace_guard!("byte::ugly_code [rust]");
    crate::extended::ugly_code::<8>(vector)
}

pub fn pack_code(input: &[u8]) -> Vec<u8> {
    let _guard = trace_guard!("byte::pack_code [rust]");
    input.to_vec()
}

pub mod binary {
    use crate::extended::CodeMetadata;
    use trace::{trace_guard, trace_vchord_print};

    const BITS: usize = 8;

    pub type BinaryLutMetadata = CodeMetadata;
    pub type BinaryLut = (BinaryLutMetadata, Vec<u8>);
    pub type BinaryCode<'a> = ((f32, f32, f32, f32), &'a [u8]);

    #[deprecated]
    pub fn preprocess(vector: &[f32]) -> BinaryLut {
        let _guard = trace_guard!("byte::binary::preprocess [rust]");
        let (metadata, elements) = crate::extended::code::<BITS>(vector);
        (metadata, super::pack_code(&elements))
    }

    pub fn ugly_preprocess(vector: &[f32]) -> BinaryLut {
        let _guard = trace_guard!("byte::binary::ugly_preprocess [rust]");
        let (metadata, elements) = crate::extended::ugly_code::<BITS>(vector);
        (metadata, super::pack_code(&elements))
    }

    pub fn accumulate(x: &[u8], y: &[u8]) -> u32 {
        let _guard = trace_guard!("byte::binary::accumulate [rust]");
        let result = simd::byte::reduce_sum_of_xy(x, y);
        trace_vchord_print!("(byte) result: {}", result);
        result
    }

    pub fn half_process_dot(
        dim: u32,
        sum: u32,
        code: CodeMetadata,
        lut: BinaryLutMetadata,
    ) -> (f32,) {
        let _guard = trace_guard!("byte::binary::half_process_dot [rust]");
        let rough = crate::extended::half_process_dot::<8, BITS>(dim, sum, code, lut);
        trace_vchord_print!("(byte) dim: {}, sum: {}, rough: {}", dim, sum, rough);
        (rough,)
    }

    pub fn half_process_l2s(
        dim: u32,
        sum: u32,
        code: CodeMetadata,
        lut: BinaryLutMetadata,
    ) -> (f32,) {
        let _guard = trace_guard!("byte::binary::half_process_l2s [rust]");
        let rough = crate::extended::half_process_l2s::<8, BITS>(dim, sum, code, lut);
        trace_vchord_print!("(byte) dim: {}, sum: {}, rough: {}", dim, sum, rough);
        (rough,)
    }

    pub fn half_process_cos(
        dim: u32,
        sum: u32,
        code: CodeMetadata,
        lut: BinaryLutMetadata,
    ) -> (f32,) {
        let _guard = trace_guard!("byte::binary::half_process_cos [rust]");
        let rough = crate::extended::half_process_cos::<8, BITS>(dim, sum, code, lut);
        trace_vchord_print!("(byte) dim: {}, sum: {}, rough: {}", dim, sum, rough);
        (rough,)
    }
}
