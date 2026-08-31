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

use crate::tuples::*;
use crate::{Opaque, freepages};
use index::accessor::Accessor1;
use index::prefetcher::{Prefetcher, PrefetcherSequenceFamily};
use index::relation::{Page, PageGuard, RelationRead, RelationWrite};
use std::marker::PhantomData;
use std::num::NonZero;
use trace::{trace_guard, trace_vchord_print};

pub struct TapeWriter<'a, R, T>
where
    R: RelationWrite + 'a,
{
    head: R::WriteGuard<'a>,
    first: u32,
    index: &'a R,
    tracking_freespace: bool,
    _phantom: PhantomData<fn(T) -> T>,
}

impl<'a, R, T> TapeWriter<'a, R, T>
where
    R: RelationWrite + 'a,
    R::Page: Page<Opaque = Opaque>,
{
    pub fn create(index: &'a R, tracking_freespace: bool) -> Self {
        let _guard = trace_guard!("TapeWriter::create [rust]");
        let mut head = index.extend(
            Opaque {
                next: u32::MAX,
                skip: u32::MAX,
            },
            tracking_freespace,
        );
        head.get_opaque_mut().skip = head.id();
        let first = head.id();
        Self {
            head,
            first,
            index,
            tracking_freespace,
            _phantom: PhantomData,
        }
    }
    pub fn first(&self) -> u32 {
        self.first
    }
    pub fn freespace(&self) -> u16 {
        let _guard = trace_guard!("TapeWriter::freespace [rust]");
        self.head.freespace()
    }
    pub fn tape_move(&mut self) {
        let _guard = trace_guard!("TapeWriter::tape_move [rust]");
        if self.head.len() == 0 {
            panic!("implementation: a clear page cannot accommodate a single tuple");
        }
        let next = self.index.extend(
            Opaque {
                next: u32::MAX,
                skip: u32::MAX,
            },
            self.tracking_freespace,
        );
        self.head.get_opaque_mut().next = next.id();
        self.head = next;
    }
}

impl<'a, R, T> TapeWriter<'a, R, T>
where
    R: RelationWrite + 'a,
    R::Page: Page<Opaque = Opaque>,
    T: Tuple,
{
    pub fn push(&mut self, x: T) -> (u32, u16) {
        let _guard = trace_guard!("TapeWriter::push [rust]");
        let bytes = T::serialize(&x);
        if let Some(i) = self.head.alloc(&bytes) {
            trace_vchord_print!("head.id: {}, i: {}", self.head.id(), i);
            (self.head.id(), i)
        } else {
            let next = self.index.extend(
                Opaque {
                    next: u32::MAX,
                    skip: u32::MAX,
                },
                self.tracking_freespace,
            );
            self.head.get_opaque_mut().next = next.id();
            self.head = next;
            if let Some(i) = self.head.alloc(&bytes) {
                trace_vchord_print!("head.id: {}, i: {}", self.head.id(), i);
                (self.head.id(), i)
            } else {
                panic!("implementation: a free page cannot accommodate a single tuple")
            }
        }
    }
    pub fn tape_put(&mut self, x: T) -> (u32, u16) {
        let _guard = trace_guard!("TapeWriter::tape_put [rust]");
        let bytes = T::serialize(&x);
        if let Some(i) = self.head.alloc(&bytes) {
            (self.head.id(), i)
        } else {
            panic!("implementation: a free page cannot accommodate a single tuple")
        }
    }
}

pub fn read_directory_tape<'b, R>(
    iter: impl Iterator<Item = R::ReadGuard<'b>>,
) -> impl Iterator<Item = u32>
where
    R: RelationRead + 'b,
{
    use std::pin::Pin;
    use std::ptr::NonNull;

    #[pin_project::pin_project]
    struct State<'b, R: RelationRead + 'b, I> {
        slice: NonNull<[u32]>,
        #[pin]
        now: Option<(R::ReadGuard<'b>, u16)>,
        iter: I,
    }

    impl<'b, R: RelationRead + 'b, I: Iterator<Item = R::ReadGuard<'b>>> State<'b, R, I> {
        fn init(self: Pin<&mut Self>) {
            let _guard = trace_guard!("State(internal)::init [rust]");
            let mut this = self.project();
            let now = this.iter.next().map(|guard| (guard, 0));
            this.now.set(now);
        }

        fn next(mut self: Pin<&mut Self>) -> Option<u32> {
            let _guard = trace_guard!("State(internal)::next [rust]");
            loop {
                let mut this = self.as_mut().project();
                // Safety: If the slice is not empty, the function will return immediately,
                // so the guard will not be moved or dropped and the slice remains valid. If
                // the slice is empty, a pointer is trivially never dangling, so it's safe
                // to use.
                #[allow(unsafe_code)]
                if let Some((first, more)) = unsafe { this.slice.as_ref() }.split_first() {
                    *this.slice = more.into();
                    return Some(*first);
                }
                // Safety: `guard` is never moved in this block
                #[allow(unsafe_code)]
                if let Some((guard, i)) = unsafe { this.now.as_mut().get_unchecked_mut() } {
                    trace_vchord_print!("guard.len: {}, i: {}", guard.len(), *i);
                    if *i < guard.len() {
                        *i += 1;
                        let bytes = guard.get(*i).expect("data corruption");
                        let tuple = DirectoryTuple::deserialize_ref(bytes);
                        *this.slice = match tuple {
                            DirectoryTupleReader::_0(tuple) => tuple.elements(),
                            DirectoryTupleReader::_1(tuple) => tuple.elements(),
                        }
                        .into();
                        continue;
                    }
                } else {
                    return None;
                }
                let now = this.iter.next().map(|guard| (guard, 0));
                this.now.set(now);
            }
        }
    }

    let mut state = Box::pin(State::<'b, R, _> {
        slice: NonNull::from(&mut []),
        now: None,
        iter,
    });

    impl<'b, R: RelationRead + 'b, I: Iterator<Item = R::ReadGuard<'b>>> Iterator
        for Pin<Box<State<'b, R, I>>>
    {
        type Item = u32;

        fn next(&mut self) -> Option<u32> {
            self.as_mut().next()
        }
    }

    state.as_mut().init();

    state
}

pub fn by_directory<'b, R>(
    p: &mut impl PrefetcherSequenceFamily<'b, R>,
    iter: impl Iterator<Item = u32>,
) -> impl Iterator<Item = R::ReadGuard<'b>>
where
    R: RelationRead + 'b,
{
    let _guard = trace_guard!("by_directory [rust]");
    let mut t = p.prefetch(iter.peekable());
    std::iter::from_fn(move || {
        let (_, mut x) = t.next()?;
        let ret = x.next().expect("should be at least one element");
        assert!(x.next().is_none(), "should be at most one element");
        Some(ret)
    })
}

pub fn by_next<'b, R>(index: &'b R, first: u32) -> impl Iterator<Item = R::ReadGuard<'b>>
where
    R: RelationRead + 'b,
    R::Page: Page<Opaque = Opaque>,
{
    let _guard = trace_guard!("by_next [rust]");
    let mut current = first;
    std::iter::from_fn(move || {
        if current != u32::MAX {
            trace_vchord_print!("call index.read");
            let guard = index.read(current);
            current = guard.get_opaque().next;
            Some(guard)
        } else {
            None
        }
    })
}

pub fn read_h1_tape<'b, R, A, T>(
    iter: impl Iterator<Item = R::ReadGuard<'b>>,
    accessor: impl Fn() -> A,
    mut callback: impl for<'a> FnMut(T, u16, f32, u32, &'a [u32]),
) where
    R: RelationRead + 'b,
    A: for<'a> Accessor1<[u8; 16], (&'a [[f32; 32]; 4], &'a [f32; 32]), Output = [T; 32]>,
{
    let _guard = trace_guard!("read_h1_tape [rust]");
    let mut x = None;
    for guard in iter {
        trace_vchord_print!("guard.len: {}", guard.len());
        for i in 1..=guard.len() {
            let bytes = guard.get(i).expect("data corruption");
            let tuple = H1Tuple::deserialize_ref(bytes);
            match tuple {
                H1TupleReader::_0(tuple) => {
                    let mut x = x.take().unwrap_or_else(&accessor);
                    x.push(tuple.elements());
                    let values = x.finish((tuple.metadata(), tuple.delta()));
                    let prefetch = tuple.prefetch();
                    let flattened = prefetch.as_flattened();
                    let step = prefetch.len();
                    for (j, value) in values.into_iter().enumerate() {
                        if j < tuple.len() as usize {
                            callback(
                                value,
                                tuple.head()[j],
                                tuple.norm()[j],
                                tuple.first()[j],
                                &flattened[j * step..][..step],
                            );
                        }
                    }
                }
                H1TupleReader::_1(tuple) => {
                    x.get_or_insert_with(&accessor).push(tuple.elements());
                }
            }
        }
    }
}

pub fn read_frozen_tape<'b, R, A, T>(
    iter: impl Iterator<Item = R::ReadGuard<'b>>,
    accessor: impl Fn() -> A,
    mut callback: impl for<'a> FnMut(T, u16, NonZero<u64>, &'a [u32]),
) where
    R: RelationRead + 'b,
    A: for<'a> Accessor1<[u8; 16], (&'a [[f32; 32]; 4], &'a [f32; 32]), Output = [T; 32]>,
{
    let _guard = trace_guard!("read_frozen_tape [rust]");
    let mut x = None;
    let mut total_guards = 0;
    let mut total_elements: i32 = 0;
    let mut total_visit: i32 = 0;
    let mut trace_disabled = 0;
    let max_iterations = trace::max_trace_iterations();
    let trace_enabled_flag = trace::trace_enabled();

    for guard in iter {
        total_guards += 1;
        trace_vchord_print!("guard {}: len={}", total_guards, guard.len());
        if trace_enabled_flag {
            if total_elements > max_iterations {
                if trace_disabled == 0 {
                    trace::disable_trace();
                    trace_disabled = 1;
                }
            }
        }

        total_elements += guard.len() as i32;
        for i in 1..=guard.len() {
            let bytes = guard.get(i).expect("data corruption");
            trace_vchord_print!("bytes length: {} for i:{}", bytes.len(), i);
            let tuple = FrozenTuple::deserialize_ref(bytes);
            match tuple {
                FrozenTupleReader::_0(tuple) => {
                    let mut x = x.take().unwrap_or_else(&accessor);
                    x.push(tuple.elements());
                    trace_vchord_print!("tuple elments: {}", tuple.elements().len());
                    let values = x.finish((tuple.metadata(), tuple.delta()));
                    trace_vchord_print!("after calculating (values len: {})", values.len());
                    let prefetch = tuple.prefetch();
                    let flattened = prefetch.as_flattened();
                    let step = prefetch.len();
                    for (j, value) in values.into_iter().enumerate() {
                        if let Some(payload) = tuple.payload()[j] {
                            total_visit = total_visit + 1;
                            callback(
                                value,
                                tuple.head()[j],
                                payload,
                                &flattened[j * step..][..step],
                            );
                        }
                    }
                }
                FrozenTupleReader::_1(tuple) => {
                    x.get_or_insert_with(&accessor).push(tuple.elements());
                }
            }
        }
    }

    if trace_disabled == 1 {
        trace::enable_trace();
        trace_vchord_print!("...");
    }
    trace_vchord_print!(
        "total guards: {}, total elements: {}, total callback visited: {}",
        total_guards,
        total_elements,
        total_visit
    );
}

pub fn read_appendable_tape<'b, R, T>(
    iter: impl Iterator<Item = R::ReadGuard<'b>>,
    mut access: impl for<'a> FnMut([f32; 4], &'a [u64], f32) -> T,
    mut callback: impl for<'a> FnMut(T, u16, NonZero<u64>, &'a [u32]),
) where
    R: RelationRead + 'b,
{
    let _guard = trace_guard!("read_appendable_tape [rust]");
    let mut total_count = 0;
    let mut guard_count = 0;
    let mut disable_trace_flag = 0;
    let threshold = trace::max_trace_iterations();
    let trace_enabled_flag = trace::trace_enabled();

    for guard in iter {
        guard_count = guard_count + 1;
        trace_vchord_print!("guard.len: {}", guard.len());
        for i in 1..=guard.len() {
            let bytes = guard.get(i).expect("data corruption");
            let tuple = AppendableTuple::deserialize_ref(bytes);
            if let Some(payload) = tuple.payload() {
                let value = access(tuple.metadata(), tuple.elements(), tuple.delta());
                callback(value, tuple.head(), payload, tuple.prefetch());
                total_count = total_count + 1;
                if trace_enabled_flag {
                    if total_count >= threshold {
                        if disable_trace_flag == 0 {
                            disable_trace_flag = 1;
                            trace::disable_trace();
                        }
                    }
                }
            }
        }
    }

    if disable_trace_flag == 1 {
        trace::enable_trace();
        trace_vchord_print!("...");
    }
    trace_vchord_print!(
        "total guard count: {}, total callback visited: {}",
        guard_count,
        total_count
    );
}

#[allow(clippy::collapsible_else_if)]
pub fn append<R: RelationRead + RelationWrite>(
    index: &R,
    first: u32,
    bytes: &[u8],
    tracking_freespace: bool,
    freepages_first: Option<u32>,
) -> (u32, u16)
where
    R::Page: Page<Opaque = Opaque>,
{
    let _guard = trace_guard!("append [rust]");
    assert!(!tracking_freespace || freepages_first.is_none());
    assert!(first != u32::MAX);
    let mut current = first;
    loop {
        let read = index.read(current);
        if read.freespace() as usize >= bytes.len() || read.get_opaque().next == u32::MAX {
            drop(read);
            let mut write = index.write(current, tracking_freespace);
            if write.get_opaque().next == u32::MAX {
                if let Some(i) = write.alloc(bytes) {
                    return (current, i);
                }
                let mut extend = {
                    if let Some(freepages_first) = freepages_first {
                        if let Some(mut guard) = freepages::alloc(index, freepages_first) {
                            guard.clear(Opaque {
                                next: u32::MAX,
                                skip: u32::MAX,
                            });
                            guard
                        } else {
                            index.extend(
                                Opaque {
                                    next: u32::MAX,
                                    skip: u32::MAX,
                                },
                                tracking_freespace,
                            )
                        }
                    } else {
                        index.extend(
                            Opaque {
                                next: u32::MAX,
                                skip: u32::MAX,
                            },
                            tracking_freespace,
                        )
                    }
                };
                write.get_opaque_mut().next = extend.id();
                drop(write);
                let fresh = extend.id();
                if let Some(i) = extend.alloc(bytes) {
                    drop(extend);
                    let mut past = index.write(first, tracking_freespace);
                    past.get_opaque_mut().skip = fresh.max(past.get_opaque().skip);
                    return (fresh, i);
                } else {
                    panic!("implementation: a clear page cannot accommodate a single tuple");
                }
            }
            if current == first && write.get_opaque().skip != first {
                current = write.get_opaque().skip;
            } else {
                current = write.get_opaque().next;
            }
        } else {
            if current == first && read.get_opaque().skip != first {
                current = read.get_opaque().skip;
            } else {
                current = read.get_opaque().next;
            }
        }
    }
}
