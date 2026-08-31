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
use crate::stack::StackIter;
use std::marker::PhantomData;
use std::ptr::NonNull;
use trace::trace_guard;

#[derive(Clone, Copy)]
pub struct HeapIter<'a, T: Copy> {
    off: u16,
    len: u16,
    pointer: NonNull<T>,
    _phantom: PhantomData<&'a T>,
}

impl<'a, T: Copy> HeapIter<'a, T> {
    #[cold]
    pub(crate) fn from_slice(slice: &'a [T]) -> Self {
        assert!(slice.len() <= 65535_usize);
        let c = NonNull::from_ref(slice).cast::<T>();
        Self {
            off: 0,
            len: slice.len() as u16,
            pointer: c,
            _phantom: PhantomData,
        }
    }
}

impl<'a, T: Copy> Iterator for HeapIter<'a, T> {
    type Item = T;

    #[inline(always)]
    fn next(&mut self) -> Option<Self::Item> {
        let _guard = trace_guard!("Iterator(HeapIter)::next [rust]");
        #[allow(unsafe_code)]
        unsafe {
            if self.off < self.len {
                let r = self.pointer.as_ptr().add(self.off as _).read();
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

impl<'a, T: Copy> ExactSizeIterator for HeapIter<'a, T> {}

#[derive(Clone, Copy)]
pub enum Iter<'a, T: Copy, const N: usize> {
    Stack(StackIter<T, N>),
    Heap(HeapIter<'a, T>),
}

impl<'a, T: Copy, const N: usize> Iter<'a, T, N> {
    #[inline(always)]
    pub fn from_slice(slice: &[T], alloc: impl Fn(&[T]) -> &'a [T]) -> Self {
        let _guard = trace_guard!("Iter::from_slice [rust]");
        assert!(slice.len() <= 65535);
        if slice.len() <= N && N <= 65535 {
            Iter::Stack(StackIter::from_slice(slice))
        } else {
            Iter::Heap(HeapIter::from_slice(alloc(slice)))
        }
    }
}

impl<'a, T: Copy, const N: usize> Iterator for Iter<'a, T, N> {
    type Item = T;

    #[inline(always)]
    fn next(&mut self) -> Option<Self::Item> {
        let _guard = trace_guard!("Iterator(Iter)::next [rust]");
        match self {
            Iter::Stack(iter) => iter.next(),
            Iter::Heap(iter) => iter.next(),
        }
    }

    #[inline(always)]
    fn size_hint(&self) -> (usize, Option<usize>) {
        match self {
            Iter::Stack(iter) => iter.size_hint(),
            Iter::Heap(iter) => iter.size_hint(),
        }
    }
}

impl<'a, T: Copy, const N: usize> ExactSizeIterator for Iter<'a, T, N> {}

#[cfg(target_pointer_width = "64")]
const _: () = {
    assert!(size_of::<Iter::<'static, u32, 1>>() == 16);
};

#[test]
fn tests() {
    let alloc = |slice: &[u32]| -> &'static [u32] {
        // make miri happy
        static GLOBAL: std::sync::Mutex<Vec<&'static [u32]>> = std::sync::Mutex::new(Vec::new());
        let pointer = Vec::leak(slice.to_vec());
        GLOBAL.lock().expect("failed to lock").push(pointer);
        pointer
    };
    for x in Iter::<u32, 5>::from_slice(&[1; 0], alloc) {
        assert_eq!(x, 1);
    }
    for x in Iter::<u32, 5>::from_slice(&[1; 1], alloc) {
        assert_eq!(x, 1);
    }
    for x in Iter::<u32, 5>::from_slice(&[1; 2], alloc) {
        assert_eq!(x, 1);
    }
    for x in Iter::<u32, 5>::from_slice(&[1; 3], alloc) {
        assert_eq!(x, 1);
    }
    for x in Iter::<u32, 5>::from_slice(&[1; 4], alloc) {
        assert_eq!(x, 1);
    }
    for x in Iter::<u32, 5>::from_slice(&[1; 5], alloc) {
        assert_eq!(x, 1);
    }
    for x in Iter::<u32, 5>::from_slice(&[1; 6], alloc) {
        assert_eq!(x, 1);
    }
    for x in Iter::<u32, 5>::from_slice(&[1; 7], alloc) {
        assert_eq!(x, 1);
    }
}
