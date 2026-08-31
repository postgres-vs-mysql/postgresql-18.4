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

pub struct LinkedVec<T> {
    inner: Vec<Vec<T>>,
    last: Vec<T>,
}

impl<T> LinkedVec<T> {
    pub fn new() -> Self {
        let _guard = trace_guard!("LinkedVec::new [rust]");
        Self {
            inner: Vec::new(),
            last: Vec::with_capacity(4096),
        }
    }
    pub fn push(&mut self, value: T) {
        let _guard = trace_guard!("LinkedVec::push [rust]");
        if self.last.len() == self.last.capacity() {
            self.reserve();
        }
        #[allow(unsafe_code)]
        unsafe {
            std::hint::assert_unchecked(self.last.len() != self.last.capacity());
        }
        self.last.push(value);
        trace_vchord_print!(
            "in LinkedVec::push, last vect len: {}, inner(vec<vect<T>>) len: {}",
            self.last.len(),
            self.inner.len()
        );
    }
    #[cold]
    fn reserve(&mut self) {
        let _guard = trace_guard!("LinkedVec::reserve [rust]");
        let fresh = Vec::with_capacity(self.last.capacity() * 4);
        self.inner.push(core::mem::replace(&mut self.last, fresh));
    }
    pub fn into_vec(self) -> Vec<T> {
        let _guard = trace_guard!("LinkedVec::into_vec [rust]");
        let mut last = self.last;
        last.reserve(self.inner.iter().map(Vec::len).sum::<usize>());
        for x in self.inner {
            last.extend(x);
        }
        last
    }
}
