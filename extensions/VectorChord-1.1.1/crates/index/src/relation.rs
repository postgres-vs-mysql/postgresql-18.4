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
use crate::fetch::Fetch;
use std::ops::{Deref, DerefMut};
use zerocopy::{FromBytes, IntoBytes};

/// # Safety
///
/// * `Opaque` must aligned to 8 bytes.
#[allow(unsafe_code)]
pub unsafe trait Opaque: Copy + Send + Sync + FromBytes + IntoBytes + 'static {}

pub trait Page: Sized + 'static {
    type Opaque: Opaque;

    #[must_use]
    fn get_opaque(&self) -> &Self::Opaque;
    #[must_use]
    fn get_opaque_mut(&mut self) -> &mut Self::Opaque;
    #[must_use]
    fn len(&self) -> u16;
    #[must_use]
    #[inline]
    fn is_empty(&self) -> bool {
        self.len() == 0
    }
    #[must_use]
    fn get(&self, i: u16) -> Option<&[u8]>;
    #[must_use]
    fn get_mut(&mut self, i: u16) -> Option<&mut [u8]>;
    #[must_use]
    fn alloc(&mut self, data: &[u8]) -> Option<u16>;
    fn free(&mut self, i: u16);
    #[must_use]
    fn freespace(&self) -> u16;
    fn clear(&mut self, opaque: Self::Opaque);
}

pub trait PageGuard {
    fn id(&self) -> u32;
}

pub trait ReadStream<'b> {
    type Relation: RelationReadTypes;
    type Guards: ExactSizeIterator<Item = <Self::Relation as RelationReadTypes>::ReadGuard<'b>>;
    type Item;
    type Inner: Iterator<Item = Self::Item>;
    fn next(&mut self) -> Option<(Self::Item, Self::Guards)>;
    fn next_if<P: FnOnce(&Self::Item) -> bool>(
        &mut self,
        predicate: P,
    ) -> Option<(Self::Item, Self::Guards)>;
    fn into_inner(self) -> Self::Inner;
}

pub trait Relation {
    type Page: Page;
}

pub trait RelationReadTypes: Relation {
    type ReadGuard<'b>: PageGuard + Deref<Target = Self::Page>;
}

pub trait RelationRead: RelationReadTypes {
    fn read(&self, id: u32) -> Self::ReadGuard<'_>;
}

pub trait RelationWriteTypes: Relation {
    type WriteGuard<'b>: PageGuard + DerefMut<Target = Self::Page>;
}

pub trait RelationWrite: RelationWriteTypes {
    fn write(&self, id: u32, tracking_freespace: bool) -> Self::WriteGuard<'_>;
    fn extend(
        &self,
        opaque: <Self::Page as Page>::Opaque,
        tracking_freespace: bool,
    ) -> Self::WriteGuard<'_>;
    fn search(&self, freespace: usize) -> Option<Self::WriteGuard<'_>>;
}

pub trait RelationPrefetch: Relation {
    fn prefetch(&self, id: u32);
}

#[derive(Debug, Clone, Copy)]
#[non_exhaustive]
pub struct Hints {
    pub full: bool,
    pub batch: bool,
}

impl Default for Hints {
    #[inline]
    fn default() -> Self {
        Self {
            full: false,
            batch: false,
        }
    }
}

impl Hints {
    #[inline]
    pub fn full(self, full: bool) -> Self {
        Self { full, ..self }
    }
    #[inline]
    pub fn batch(self, batch: bool) -> Self {
        Self { batch, ..self }
    }
}

pub trait RelationReadStreamTypes: RelationReadTypes {
    type ReadStream<'b, I: Iterator>: ReadStream<'b, Item = I::Item, Relation = Self>
    where
        I::Item: Fetch<'b>;
}

pub trait RelationReadStream: RelationReadStreamTypes {
    fn read_stream<'b, I: Iterator>(&'b self, iter: I, hints: Hints) -> Self::ReadStream<'b, I>
    where
        I::Item: Fetch<'b>;
}
