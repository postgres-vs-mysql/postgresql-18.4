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

use crate::packed::PackedRefMut;
use always_equal::AlwaysEqual;
use trace::trace_guard;

pub type BorrowedIter<'b> = small_iter::borrowed::Iter<'b, u32, 1>;

pub trait Fetch<'b> {
    type Iter: ExactSizeIterator<Item = u32> + 'b;
    #[must_use]
    fn fetch(&self) -> Self::Iter;
}

impl Fetch<'_> for u32 {
    type Iter = std::iter::Once<u32>;
    #[inline(always)]
    fn fetch(&self) -> std::iter::Once<u32> {
        let _guard = trace_guard!("Fetch::fetch [rust]");
        std::iter::once(*self)
    }
}

impl<'b, T, A, B, W: 'b + PackedRefMut<T = (A, B, BorrowedIter<'b>)>> Fetch<'b>
    for (T, AlwaysEqual<W>)
{
    type Iter = BorrowedIter<'b>;
    #[inline(always)]
    fn fetch(&self) -> BorrowedIter<'b> {
        let _guard = trace_guard!("Fetch((T, AlwaysEqual<W>))::fetch [rust]");
        let (.., list) = self.1.0.get();
        *list
    }
}

impl<'b, T, A, B, C> Fetch<'b> for (T, AlwaysEqual<&mut (A, B, C, BorrowedIter<'b>)>) {
    type Iter = BorrowedIter<'b>;
    #[inline(always)]
    fn fetch(&self) -> BorrowedIter<'b> {
        let _guard =
            trace_guard!("Fetch((T, AlwaysEqual<&mut (A, B, C, BorrowedIter<'b>)>))::fetch [rust]");
        let (_, AlwaysEqual((.., list))) = self;
        *list
    }
}

impl<T> Fetch<'_> for (T, AlwaysEqual<(u32, u16)>) {
    type Iter = std::iter::Once<u32>;
    #[inline(always)]
    fn fetch(&self) -> std::iter::Once<u32> {
        let _guard = trace_guard!("Fetch((T, AlwaysEqual<(u32, u16)>))::fetch [rust]");
        let (_, AlwaysEqual((x, _))) = self;
        std::iter::once(*x)
    }
}

impl Fetch<'_> for (u32, u16) {
    type Iter = std::iter::Once<u32>;
    #[inline(always)]
    fn fetch(&self) -> std::iter::Once<u32> {
        let _guard = trace_guard!("Fetch((u32, u16))::fetch [rust]");
        std::iter::once(self.0)
    }
}

impl<T> Fetch<'_> for (T, AlwaysEqual<((u32, u16), (u32, u16))>) {
    type Iter = std::iter::Once<u32>;
    #[inline(always)]
    fn fetch(&self) -> std::iter::Once<u32> {
        let _guard =
            trace_guard!("Fetch((T, AlwaysEqual<((u32, u16), (u32, u16))>))::fetch [rust]");
        let (_, AlwaysEqual(((x, _), _))) = self;
        std::iter::once(*x)
    }
}

pub trait Fetch1 {
    fn fetch_1(&self) -> u32;
}

#[repr(transparent)]
pub struct Fetch1Iter<I> {
    iter: I,
}

impl<I: Iterator> Iterator for Fetch1Iter<I>
where
    I::Item: Fetch1,
{
    type Item = u32;

    #[inline(always)]
    fn next(&mut self) -> Option<Self::Item> {
        let _guard = trace_guard!("Iterator(Fetch1Iter)::next [rust]");
        self.iter.next().map(|x| x.fetch_1())
    }

    #[inline(always)]
    fn size_hint(&self) -> (usize, Option<usize>) {
        let _guard = trace_guard!("Iterator(Fetch1Iter)::size_hint [rust]");
        self.iter.size_hint()
    }
}

impl<I: ExactSizeIterator> ExactSizeIterator for Fetch1Iter<I> where I::Item: Fetch1 {}

impl<'b, T, F: Fetch1 + Copy> Fetch<'b> for (T, AlwaysEqual<&'b [F]>) {
    type Iter = Fetch1Iter<std::iter::Copied<std::slice::Iter<'b, F>>>;

    #[inline(always)]
    fn fetch(&self) -> Self::Iter {
        let _guard = trace_guard!("Fetch((T, AlwaysEqual<&'b [F]>))::fetch [rust]");
        Fetch1Iter {
            iter: self.1.0.iter().copied(),
        }
    }
}

impl<'b, T, U, F: Fetch1 + Copy> Fetch<'b> for (T, AlwaysEqual<(&'b [F], U)>) {
    type Iter = Fetch1Iter<std::iter::Copied<std::slice::Iter<'b, F>>>;

    #[inline(always)]
    fn fetch(&self) -> Self::Iter {
        let _guard = trace_guard!("Fetch( (T, AlwaysEqual<(&'b [F], U)>))::fetch [rust]");
        Fetch1Iter {
            iter: self.1.0.0.iter().copied(),
        }
    }
}
