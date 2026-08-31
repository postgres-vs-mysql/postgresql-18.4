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
use std::mem::MaybeUninit;
use trace::trace_guard;

#[derive(Clone, Copy)]
pub struct StackIter<T: Copy, const N: usize> {
    off: u16,
    len: u16,
    buffer: [MaybeUninit<T>; N],
}

impl<T: Copy, const N: usize> StackIter<T, N> {
    #[inline(always)]
    pub(crate) fn from_slice(slice: &[T]) -> Self {
        assert!(slice.len() <= N && N <= 65535);
        Self {
            off: 0,
            len: slice.len() as u16,
            buffer: {
                let mut buffer = [const { MaybeUninit::uninit() }; N];
                for i in 0..slice.len() {
                    buffer[i] = MaybeUninit::new(slice[i]);
                }
                buffer
            },
        }
    }
}

impl<T: Copy, const N: usize> Iterator for StackIter<T, N> {
    type Item = T;

    #[inline(always)]
    fn next(&mut self) -> Option<Self::Item> {
        let _guard = trace_guard!("Iterator(StackIter)::next [rust]");
        #[allow(unsafe_code)]
        unsafe {
            if self.off < self.len {
                let r = self.buffer[self.off as usize].assume_init();
                self.off += 1;
                Some(r)
            } else {
                None
            }
        }
    }

    #[inline(always)]
    fn size_hint(&self) -> (usize, Option<usize>) {
        let size = (self.len - self.off) as usize;
        (size, Some(size))
    }
}

impl<T: Copy, const N: usize> ExactSizeIterator for StackIter<T, N> {}
