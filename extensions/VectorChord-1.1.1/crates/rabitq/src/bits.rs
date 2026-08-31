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

#[derive(Debug, Clone, Copy)]
#[repr(u8)]
pub enum Bits {
    _1 = 1,
    _2 = 2,
}

impl TryFrom<u8> for Bits {
    type Error = ();

    fn try_from(value: u8) -> Result<Self, Self::Error> {
        let _guard = trace_guard!("TryFrom(Bits)::try_from [rust]");
        match value {
            1 => Ok(Self::_1),
            2 => Ok(Self::_2),
            _ => Err(()),
        }
    }
}

pub fn code(bits: Bits, vector: &[f32]) -> Code {
    let _guard = trace_guard!("bits::code [rust]");
    match bits {
        Bits::_1 => crate::extended::code::<1>(vector),
        Bits::_2 => crate::extended::code::<2>(vector),
    }
}

pub fn ugly_code(bits: Bits, vector: &[f32]) -> Code {
    let _guard = trace_guard!("bits::ugly_code [rust]");
    match bits {
        Bits::_1 => crate::extended::ugly_code::<1>(vector),
        Bits::_2 => crate::extended::ugly_code::<2>(vector),
    }
}

pub fn pack_code(bits: Bits, input: &[u8]) -> Vec<u64> {
    let _guard = trace_guard!("bits::pack_code [rust]");
    match bits {
        Bits::_1 => crate::extended::pack_code::<1>(input)
            .into_iter()
            .flatten()
            .collect(),
        Bits::_2 => crate::extended::pack_code::<2>(input)
            .into_iter()
            .flatten()
            .collect(),
    }
}

pub mod binary {
    use crate::bits::Bits;
    use crate::extended::CodeMetadata;
    use trace::{trace_guard, trace_vchord_print};

    const BITS: usize = 4;

    pub type BinaryLutMetadata = CodeMetadata;
    pub type BinaryLut = (BinaryLutMetadata, [Vec<u64>; BITS]);
    pub type BinaryCode<'a> = ((f32, f32, f32, f32), &'a [u8]);

    pub fn preprocess(vector: &[f32]) -> BinaryLut {
        let _guard = trace_guard!("bits::binary::preprocess [rust]");
        let (metadata, elements) = crate::extended::code::<BITS>(vector);
        (metadata, crate::extended::pack_code::<BITS>(&elements))
    }

    pub fn ugly_preprocess(vector: &[f32]) -> BinaryLut {
        let _guard = trace_guard!("bits::binary::ugly_preprocess [rust]");
        let (metadata, elements) = crate::extended::ugly_code::<BITS>(vector);
        (metadata, crate::extended::pack_code::<BITS>(&elements))
    }

    pub fn accumulate(bits: Bits, lhs: &[u64], rhs: &[Vec<u64>; BITS]) -> u32 {
        let _guard = trace_guard!("bits::binary::accumulate [rust]");
        let result = match bits {
            Bits::_1 => crate::extended::accumulate::<1, BITS>(lhs, rhs),
            Bits::_2 => crate::extended::accumulate::<2, BITS>(lhs, rhs),
        };

        trace_vchord_print!("(bits) result: {}", result);
        result
    }

    pub fn half_process_dot(
        bits: Bits,
        dim: u32,
        sum: u32,
        code: CodeMetadata,
        lut: BinaryLutMetadata,
    ) -> (f32,) {
        let _guard = trace_guard!("bits::binary::half_process_dot [rust]");
        trace_vchord_print!("mod binary for extented");
        let rough = match bits {
            Bits::_1 => crate::extended::half_process_dot::<1, BITS>(dim, sum, code, lut),
            Bits::_2 => crate::extended::half_process_dot::<2, BITS>(dim, sum, code, lut),
        };
        trace_vchord_print!("(bits) dim: {}, sum: {}, rough: {}", dim, sum, rough);
        (rough,)
    }

    pub fn half_process_l2s(
        bits: Bits,
        dim: u32,
        sum: u32,
        code: CodeMetadata,
        lut: BinaryLutMetadata,
    ) -> (f32,) {
        let _guard = trace_guard!("bits::binary::half_process_l2s [rust]");
        let rough = match bits {
            Bits::_1 => crate::extended::half_process_l2s::<1, BITS>(dim, sum, code, lut),
            Bits::_2 => crate::extended::half_process_l2s::<2, BITS>(dim, sum, code, lut),
        };
        trace_vchord_print!("(bits) dim: {}, sum: {}, rough: {}", dim, sum, rough);
        (rough,)
    }
}
