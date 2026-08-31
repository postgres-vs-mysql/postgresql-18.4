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

use crate::{VectorBorrowed, VectorOwned};
use distance::Distance;
use trace::trace_guard;

#[derive(Debug, Clone)]
pub struct Rabitq8Owned {
    dim: u32,
    sum_of_x2: f32,
    norm_of_lattice: f32,
    sum_of_code: f32,
    sum_of_abs_x: f32,
    packed_code: Vec<u8>,
}

impl Rabitq8Owned {
    #[inline(always)]
    pub fn new(
        dim: u32,
        sum_of_x2: f32,
        norm_of_lattice: f32,
        sum_of_code: f32,
        sum_of_abs_x: f32,
        packed_code: Vec<u8>,
    ) -> Self {
        let _guard = trace_guard!("Rabitq8Owned::new [rust]");
        Self::new_checked(
            dim,
            sum_of_x2,
            norm_of_lattice,
            sum_of_code,
            sum_of_abs_x,
            packed_code,
        )
        .expect("invalid data")
    }

    #[inline(always)]
    pub fn new_checked(
        dim: u32,
        sum_of_x2: f32,
        norm_of_lattice: f32,
        sum_of_code: f32,
        sum_of_abs_x: f32,
        packed_code: Vec<u8>,
    ) -> Option<Self> {
        let _guard = trace_guard!("Rabitq8Owned::new_checked [rust]");
        if !(1..=65535).contains(&dim) {
            return None;
        }
        if dim.div_ceil(1) as usize != packed_code.len() {
            return None;
        }
        #[allow(unsafe_code)]
        Some(unsafe {
            Self::new_unchecked(
                dim,
                sum_of_x2,
                norm_of_lattice,
                sum_of_code,
                sum_of_abs_x,
                packed_code,
            )
        })
    }

    /// # Safety
    ///
    /// * `dim` must not be zero.
    /// * `dim` must be less than 65536.
    /// * `dim` must be equal to `code.len()`.
    #[allow(unsafe_code)]
    #[inline(always)]
    pub unsafe fn new_unchecked(
        dim: u32,
        sum_of_x2: f32,
        norm_of_lattice: f32,
        sum_of_code: f32,
        sum_of_abs_x: f32,
        packed_code: Vec<u8>,
    ) -> Self {
        let _guard = trace_guard!("Rabitq8Owned::new_unchecked [rust]");
        Self {
            dim,
            sum_of_x2,
            norm_of_lattice,
            sum_of_code,
            sum_of_abs_x,
            packed_code,
        }
    }
}

impl VectorOwned for Rabitq8Owned {
    type Borrowed<'a> = Rabitq8Borrowed<'a>;

    #[inline(always)]
    fn as_borrowed(&self) -> Rabitq8Borrowed<'_> {
        let _guard = trace_guard!("VectorOwned(Rabitq8Owned)::as_borrowed [rust]");
        Rabitq8Borrowed {
            dim: self.dim,
            sum_of_x2: self.sum_of_x2,
            norm_of_lattice: self.norm_of_lattice,
            sum_of_code: self.sum_of_code,
            sum_of_abs_x: self.sum_of_abs_x,
            packed_code: self.packed_code.as_slice(),
        }
    }
}

#[derive(Debug, Clone, Copy)]
pub struct Rabitq8Borrowed<'a> {
    dim: u32,
    sum_of_x2: f32,
    norm_of_lattice: f32,
    sum_of_code: f32,
    sum_of_abs_x: f32,
    packed_code: &'a [u8],
}

impl<'a> Rabitq8Borrowed<'a> {
    #[inline(always)]
    pub fn new(
        dim: u32,
        sum_of_x2: f32,
        norm_of_lattice: f32,
        sum_of_code: f32,
        sum_of_abs_x: f32,
        packed_code: &'a [u8],
    ) -> Self {
        let _guard = trace_guard!("Rabitq8Borrowed::new [rust]");
        Self::new_checked(
            dim,
            sum_of_x2,
            norm_of_lattice,
            sum_of_code,
            sum_of_abs_x,
            packed_code,
        )
        .expect("invalid data")
    }

    #[inline(always)]
    pub fn new_checked(
        dim: u32,
        sum_of_x2: f32,
        norm_of_lattice: f32,
        sum_of_code: f32,
        sum_of_abs_x: f32,
        packed_code: &'a [u8],
    ) -> Option<Self> {
        let _guard = trace_guard!("Rabitq8Borrowed::new_checked [rust]");
        if !(1..=65535).contains(&dim) {
            return None;
        }
        if dim.div_ceil(1) as usize != packed_code.len() {
            return None;
        }
        #[allow(unsafe_code)]
        Some(unsafe {
            Self::new_unchecked(
                dim,
                sum_of_x2,
                norm_of_lattice,
                sum_of_code,
                sum_of_abs_x,
                packed_code,
            )
        })
    }

    /// # Safety
    ///
    /// * `dim` must not be zero.
    /// * `dim` must be less than 65536.
    /// * `dim` must be equal to `code.len()`.
    #[allow(unsafe_code)]
    #[inline(always)]
    pub unsafe fn new_unchecked(
        dim: u32,
        sum_of_x2: f32,
        norm_of_lattice: f32,
        sum_of_code: f32,
        sum_of_abs_x: f32,
        packed_code: &'a [u8],
    ) -> Self {
        let _guard = trace_guard!("Rabitq8Borrowed::new_unchecked [rust]");
        Self {
            dim,
            sum_of_x2,
            norm_of_lattice,
            sum_of_code,
            sum_of_abs_x,
            packed_code,
        }
    }

    #[inline(always)]
    pub fn sum_of_x2(&self) -> f32 {
        self.sum_of_x2
    }

    #[inline(always)]
    pub fn norm_of_lattice(&self) -> f32 {
        self.norm_of_lattice
    }

    #[inline(always)]
    pub fn sum_of_code(&self) -> f32 {
        self.sum_of_code
    }

    #[inline(always)]
    pub fn sum_of_abs_x(&self) -> f32 {
        self.sum_of_abs_x
    }

    #[inline(always)]
    pub fn packed_code(&self) -> &'a [u8] {
        self.packed_code
    }

    #[inline(always)]
    pub fn unpacked_code(&self) -> impl Iterator<Item = u8> {
        self.packed_code.iter().copied()
    }
}

impl VectorBorrowed for Rabitq8Borrowed<'_> {
    type Owned = Rabitq8Owned;

    #[inline(always)]
    fn dim(&self) -> u32 {
        self.dim
    }

    #[inline(always)]
    fn own(&self) -> Rabitq8Owned {
        let _guard = trace_guard!("VectorBorrowed(Rabitq8Borrowed)::own [rust]");
        Rabitq8Owned {
            dim: self.dim,
            sum_of_x2: self.sum_of_x2,
            norm_of_lattice: self.norm_of_lattice,
            sum_of_code: self.sum_of_code,
            sum_of_abs_x: self.sum_of_abs_x,
            packed_code: self.packed_code.to_owned(),
        }
    }

    #[inline(always)]
    fn norm(&self) -> f32 {
        let _guard = trace_guard!("VectorBorrowed(Rabitq8Borrowed)::norm [rust]");
        self.sum_of_x2.sqrt()
    }

    #[inline(always)]
    fn operator_dot(self, rhs: Self) -> Distance {
        let _guard = trace_guard!("VectorBorrowed(Rabitq8Borrowed)::operator_dot [rust]");
        let dim = self.dim();
        let sum = rabitq::byte::binary::accumulate(self.packed_code, rhs.packed_code);
        Distance::from_f32(
            rabitq::byte::binary::half_process_dot(
                dim,
                sum,
                rabitq::byte::CodeMetadata {
                    dis_u_2: self.sum_of_x2,
                    norm_of_lattice: self.norm_of_lattice,
                    sum_of_code: self.sum_of_code,
                },
                rabitq::byte::CodeMetadata {
                    dis_u_2: rhs.sum_of_x2,
                    norm_of_lattice: rhs.norm_of_lattice,
                    sum_of_code: rhs.sum_of_code,
                },
            )
            .0,
        )
    }

    #[inline(always)]
    fn operator_l2s(self, rhs: Self) -> Distance {
        let _guard = trace_guard!("VectorBorrowed(Rabitq8Borrowed)::operator_l2s [rust]");
        let dim = self.dim();
        let sum = rabitq::byte::binary::accumulate(self.packed_code, rhs.packed_code);
        Distance::from_f32(
            rabitq::byte::binary::half_process_l2s(
                dim,
                sum,
                rabitq::byte::CodeMetadata {
                    dis_u_2: self.sum_of_x2,
                    norm_of_lattice: self.norm_of_lattice,
                    sum_of_code: self.sum_of_code,
                },
                rabitq::byte::CodeMetadata {
                    dis_u_2: rhs.sum_of_x2,
                    norm_of_lattice: rhs.norm_of_lattice,
                    sum_of_code: rhs.sum_of_code,
                },
            )
            .0,
        )
    }

    #[inline(always)]
    fn operator_cos(self, rhs: Self) -> Distance {
        let _guard = trace_guard!("VectorBorrowed(Rabitq8Borrowed)::operator_cos [rust]");
        let dim = self.dim();
        let sum = rabitq::byte::binary::accumulate(self.packed_code, rhs.packed_code);
        Distance::from_f32(
            rabitq::byte::binary::half_process_cos(
                dim,
                sum,
                rabitq::byte::CodeMetadata {
                    dis_u_2: self.sum_of_x2,
                    norm_of_lattice: self.norm_of_lattice,
                    sum_of_code: self.sum_of_code,
                },
                rabitq::byte::CodeMetadata {
                    dis_u_2: rhs.sum_of_x2,
                    norm_of_lattice: rhs.norm_of_lattice,
                    sum_of_code: rhs.sum_of_code,
                },
            )
            .0,
        )
    }

    #[inline(always)]
    fn operator_hamming(self, _: Self) -> Distance {
        unimplemented!()
    }

    #[inline(always)]
    fn operator_jaccard(self, _: Self) -> Distance {
        unimplemented!()
    }

    #[inline(always)]
    fn function_normalize(&self) -> Rabitq8Owned {
        let _guard = trace_guard!("VectorBorrowed(Rabitq8Borrowed)::function_normalize [rust]");
        Rabitq8Owned {
            dim: self.dim,
            sum_of_x2: 1.0,
            norm_of_lattice: self.norm_of_lattice,
            sum_of_code: self.sum_of_code,
            sum_of_abs_x: self.sum_of_abs_x / self.sum_of_x2.sqrt(),
            packed_code: self.packed_code.to_owned(),
        }
    }

    fn operator_add(&self, _: Self) -> Self::Owned {
        unimplemented!()
    }

    fn operator_sub(&self, _: Self) -> Self::Owned {
        unimplemented!()
    }

    fn operator_mul(&self, _: Self) -> Self::Owned {
        unimplemented!()
    }

    fn operator_and(&self, _: Self) -> Self::Owned {
        unimplemented!()
    }

    fn operator_or(&self, _: Self) -> Self::Owned {
        unimplemented!()
    }

    fn operator_xor(&self, _: Self) -> Self::Owned {
        unimplemented!()
    }
}
