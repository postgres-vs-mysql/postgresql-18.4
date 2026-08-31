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

pub trait Bump: 'static {
    #[allow(clippy::mut_from_ref)]
    fn alloc<T: Copy>(&self, value: T) -> &mut T;
    #[allow(clippy::mut_from_ref)]
    fn alloc_slice<T: Copy>(&self, slice: &[T]) -> &mut [T];
}

impl Bump for bumpalo::Bump {
    #[inline]
    fn alloc<T: Copy>(&self, value: T) -> &mut T {
        self.alloc(value)
    }

    #[inline]
    fn alloc_slice<T: Copy>(&self, slice: &[T]) -> &mut [T] {
        self.alloc_slice_copy(slice)
    }
}
