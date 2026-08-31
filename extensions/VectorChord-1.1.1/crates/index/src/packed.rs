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

pub trait PackedRefMut {
    type T;
    fn get(&self) -> &Self::T;
    fn get_mut(&mut self) -> &mut Self::T;
}

impl<T> PackedRefMut for &mut T {
    type T = T;
    #[inline(always)]
    fn get(&self) -> &T {
        self
    }
    #[inline(always)]
    fn get_mut(&mut self) -> &mut T {
        self
    }
}

#[repr(Rust, packed(4))]
pub struct PackedRefMut4<'b, T>(pub &'b mut T);

impl<'b, T> PackedRefMut for PackedRefMut4<'b, T> {
    type T = T;
    #[inline(always)]
    fn get(&self) -> &T {
        self.0
    }
    #[inline(always)]
    fn get_mut(&mut self) -> &mut T {
        self.0
    }
}

#[repr(Rust, packed(8))]
pub struct PackedRefMut8<'b, T>(pub &'b mut T);

impl<'a, T> PackedRefMut for PackedRefMut8<'a, T> {
    type T = T;
    #[inline(always)]
    fn get(&self) -> &T {
        self.0
    }
    #[inline(always)]
    fn get_mut(&mut self) -> &mut T {
        self.0
    }
}
