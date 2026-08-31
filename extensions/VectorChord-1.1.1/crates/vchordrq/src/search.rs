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

use crate::closure_lifetime_binder::{id_0, id_1, id_2};
use crate::linked_vec::LinkedVec;
use crate::operator::*;
use crate::tape::{by_directory, by_next};
use crate::tuples::*;
use crate::{Opaque, centroids, tape};
use always_equal::AlwaysEqual;
use distance::Distance;
use index::accessor::{DefaultWithDimension, FunctionalAccessor, LAccess};
use index::bump::Bump;
use index::fetch::BorrowedIter;
use index::packed::{PackedRefMut4, PackedRefMut8};
use index::prefetcher::{Prefetcher, PrefetcherHeapFamily, PrefetcherSequenceFamily};
use index::relation::{Page, RelationRead};
use std::cmp::Reverse;
use std::collections::BinaryHeap;
use std::num::NonZero;
use trace::{trace_guard, trace_vchord_instant_print, trace_vchord_print};
use vector::{VectorBorrowed, VectorOwned};

type Extra1<'b> = &'b mut (u32, f32, u16, BorrowedIter<'b>);

pub fn default_search<'b, R: RelationRead, O: Operator>(
    index: &'b R,
    vector: <O::Vector as VectorOwned>::Borrowed<'_>,
    probes: Vec<u32>,
    epsilon: f32,
    bump: &'b impl Bump,
    mut prefetch_h1_vectors: impl PrefetcherHeapFamily<'b, R>,
    mut prefetch_h0_tuples: impl PrefetcherSequenceFamily<'b, R>,
) -> Vec<(
    (Reverse<Distance>, AlwaysEqual<()>),
    AlwaysEqual<PackedRefMut4<'b, (NonZero<u64>, u16, BorrowedIter<'b>)>>,
)>
where
    R::Page: Page<Opaque = Opaque>,
{
    let _guard = trace_guard!("vchordrq::search::default_search [rust]");
    let meta_guard = index.read(0);
    let meta_bytes = meta_guard.get(1).expect("data corruption");
    let meta_tuple = MetaTuple::deserialize_ref(meta_bytes);
    let dim = meta_tuple.dim();
    let is_residual = meta_tuple.is_residual();
    let height_of_root = meta_tuple.height_of_root();
    let cells = meta_tuple.cells().to_vec();
    assert_eq!(dim, vector.dim(), "unmatched dimensions");
    trace_vchord_print!(
        "dimensions: {}, height_of_root: {}, probes len: {}, epsilon: {}",
        dim,
        height_of_root,
        probes.len(),
        epsilon
    );
    if height_of_root as usize != 1 + probes.len() {
        trace_vchord_instant_print!(
            "usage: need {} probes, but {} probes provided",
            height_of_root - 1,
            probes.len()
        );
        panic!(
            "usage: need {} probes, but {} probes provided",
            height_of_root - 1,
            probes.len()
        );
    }
    debug_assert_eq!(cells[(height_of_root - 1) as usize], 1);

    type State = Vec<(Reverse<Distance>, AlwaysEqual<f32>, AlwaysEqual<u32>)>;
    let mut state: State = if is_residual {
        let prefetch =
            BorrowedIter::from_slice(meta_tuple.centroid_prefetch(), |x| bump.alloc_slice(x));
        let head = meta_tuple.centroid_head();
        let distance = centroids::read::<R, O, _>(
            prefetch.map(|id| index.read(id)),
            head,
            LAccess::new(
                O::Vector::unpack(vector),
                O::DistanceAccessor::default_with_dimension(dim),
            ),
        );
        let norm = meta_tuple.centroid_norm();
        let first = meta_tuple.first();
        trace_vchord_print!("slow path");
        trace_vchord_print!("norm: {}", norm);
        vec![(Reverse(distance), AlwaysEqual(norm), AlwaysEqual(first))]
    } else {
        // fast path
        trace_vchord_print!("fast path");
        let distance = Distance::ZERO;
        let norm = meta_tuple.centroid_norm();
        let first = meta_tuple.first();
        trace_vchord_print!("norm: {}", norm);
        vec![(Reverse(distance), AlwaysEqual(norm), AlwaysEqual(first))]
    };

    drop(meta_guard);
    let lut = O::Vector::preprocess(vector);

    let mut step = |state: State| {
        let mut results = LinkedVec::<(_, AlwaysEqual<Extra1<'b>>)>::new();
        trace_vchord_print!("this loop will run n times: {}", state.len());
        for (Reverse(dis_f), AlwaysEqual(norm), AlwaysEqual(first)) in state {
            tape::read_h1_tape::<R, _, _>(
                by_next(index, first),
                || O::block_access(&lut.0, is_residual, dis_f.to_f32(), norm),
                |(rough, err), head, norm, first, prefetch| {
                    let lowerbound = Distance::from_f32(rough - err * epsilon);
                    trace_vchord_print!("lowerbound: {}", lowerbound.to_f32());
                    results.push((
                        Reverse(lowerbound),
                        AlwaysEqual(bump.alloc((
                            first,
                            norm,
                            head,
                            BorrowedIter::from_slice(prefetch, |x| bump.alloc_slice(x)),
                        ))),
                    ));
                },
            );
        }
        let mut heap = prefetch_h1_vectors.prefetch(results.into_vec());
        let mut cache = BinaryHeap::<(_, _, _)>::new();
        std::iter::from_fn(move || {
            while let Some(((Reverse(_), AlwaysEqual(&mut (first, norm, head, ..))), prefetch)) =
                heap.next_if(|(d, _)| Some(*d) > cache.peek().map(|(d, ..)| *d))
            {
                let distance = centroids::read::<R, O, _>(
                    prefetch,
                    head,
                    LAccess::new(
                        O::Vector::unpack(vector),
                        O::DistanceAccessor::default_with_dimension(dim),
                    ),
                );
                cache.push((Reverse(distance), AlwaysEqual(norm), AlwaysEqual(first)));
            }
            cache.pop()
        })
    };

    for i in 1..height_of_root {
        trace_vchord_print!(
            "probes[{}]: {}, cells[{}]: {}",
            i - 1,
            probes[i as usize - 1],
            height_of_root - 1 - i,
            cells[(height_of_root - 1 - i) as usize]
        );
        let partial_scan = probes[i as usize - 1] < cells[(height_of_root - 1 - i) as usize];
        if partial_scan || is_residual {
            state = step(state).take(probes[i as usize - 1] as _).collect();
            trace_vchord_print!("slow path for {}", i);
        } else {
            // fast path
            trace_vchord_print!("fast path for {}", i);
            let mut results = LinkedVec::new();
            trace_vchord_print!("this loop will run n times: {}", state.len());
            for (Reverse(_), AlwaysEqual(_), AlwaysEqual(first)) in state {
                tape::read_h1_tape::<R, _, _>(
                    by_next(index, first),
                    || FunctionalAccessor::new((), id_0(|_, _| ()), id_1(|_, _| [(); _])),
                    |(), _, norm, first, _| {
                        results.push((
                            Reverse(Distance::ZERO),
                            AlwaysEqual(norm),
                            AlwaysEqual(first),
                        ));
                    },
                );
            }
            state = results.into_vec();
        }
    }

    let mut results = LinkedVec::<(_, AlwaysEqual<_>)>::new();
    trace_vchord_print!("now we do loop here");
    let mut loop_count = 0;
    let mut trace_disable_flag = 0;
    let min_trace_iterations = trace::min_trace_iterations();
    let trace_enabled_flag = trace::trace_enabled();

    trace_vchord_print!("this loop will run n times: {}", state.len());
    for (Reverse(dis_f), AlwaysEqual(norm), AlwaysEqual(first)) in state {
        let jump_guard = index.read(first);
        let jump_bytes = jump_guard.get(1).expect("data corruption");
        let jump_tuple = JumpTuple::deserialize_ref(jump_bytes);
        loop_count = loop_count + 1;

        if trace_enabled_flag {
            if loop_count > min_trace_iterations {
                if trace_disable_flag == 0 {
                    trace_disable_flag = 1;
                    trace::disable_trace();
                }
            }
        }
        trace_vchord_print!("set callback");
        let mut callback = id_2(|(rough, err), head, payload, prefetch| {
            let lowerbound = Distance::from_f32(rough - err * epsilon);
            trace_vchord_print!("lowerbound: {}", lowerbound.to_f32());
            results.push((
                (Reverse(lowerbound), AlwaysEqual(())),
                AlwaysEqual(PackedRefMut4(bump.alloc((
                    payload,
                    head,
                    BorrowedIter::from_slice(prefetch, |x| bump.alloc_slice(x)),
                )))),
            ));
        });
        if prefetch_h0_tuples.is_not_plain() {
            trace_vchord_print!("prefetch_h0_tuples is not plain");
            let directory =
                tape::read_directory_tape::<R>(by_next(index, jump_tuple.directory_first()));
            tape::read_frozen_tape::<R, _, _>(
                by_directory(&mut prefetch_h0_tuples, directory),
                || O::block_access(&lut.0, is_residual, dis_f.to_f32(), norm),
                &mut callback,
            );
        } else {
            trace_vchord_print!("prefetch_h0_tuples is plain");
            tape::read_frozen_tape::<R, _, _>(
                by_next(index, jump_tuple.frozen_first()),
                || O::block_access(&lut.0, is_residual, dis_f.to_f32(), norm),
                &mut callback,
            );
        }
        trace_vchord_print!("call read_appendable_tape");
        tape::read_appendable_tape::<R, _>(
            by_next(index, jump_tuple.appendable_first()),
            O::binary_access(&lut.1, is_residual, dis_f.to_f32(), norm),
            &mut callback,
        );
        trace_vchord_print!("call read_appendable_tape over");
    }

    if trace_disable_flag == 1 {
        trace::enable_trace();
        trace_vchord_print!("...");
        trace_vchord_print!("loop count: {}", loop_count);
    }
    trace_vchord_print!("we do loop over");
    results.into_vec()
}

pub fn maxsim_search<'b, R: RelationRead, O: Operator>(
    index: &'b R,
    vector: <O::Vector as VectorOwned>::Borrowed<'_>,
    probes: Vec<u32>,
    epsilon: f32,
    mut threshold: u32,
    bump: &'b impl Bump,
    mut prefetch_h1_vectors: impl PrefetcherHeapFamily<'b, R>,
    mut prefetch_h0_tuples: impl PrefetcherSequenceFamily<'b, R>,
) -> (
    Vec<(
        (Reverse<Distance>, AlwaysEqual<Distance>),
        AlwaysEqual<PackedRefMut8<'b, (NonZero<u64>, u16, BorrowedIter<'b>)>>,
    )>,
    Distance,
)
where
    R::Page: Page<Opaque = Opaque>,
{
    let _guard = trace_guard!("vchordrq::search::maxsim_search [rust]");
    let meta_guard = index.read(0);
    let meta_bytes = meta_guard.get(1).expect("data corruption");
    let meta_tuple = MetaTuple::deserialize_ref(meta_bytes);
    let dim = meta_tuple.dim();
    let is_residual = meta_tuple.is_residual();
    let height_of_root = meta_tuple.height_of_root();
    let cells = meta_tuple.cells().to_vec();
    assert_eq!(dim, vector.dim(), "unmatched dimensions");
    trace_vchord_print!(
        "dimensions: {}, height_of_root: {}, probes len: {}, epsilon: {}",
        dim,
        height_of_root,
        probes.len(),
        epsilon
    );
    if height_of_root as usize != 1 + probes.len() {
        trace_vchord_instant_print!(
            "usage: need {} probes, but {} probes provided",
            height_of_root - 1,
            probes.len()
        );
        panic!(
            "usage: need {} probes, but {} probes provided",
            height_of_root - 1,
            probes.len()
        );
    }
    debug_assert_eq!(cells[(height_of_root - 1) as usize], 1);

    type State = Vec<(Reverse<Distance>, AlwaysEqual<f32>, AlwaysEqual<u32>)>;
    let mut state: State = if is_residual {
        let prefetch =
            BorrowedIter::from_slice(meta_tuple.centroid_prefetch(), |x| bump.alloc_slice(x));
        let head = meta_tuple.centroid_head();
        let distance = centroids::read::<R, O, _>(
            prefetch.map(|id| index.read(id)),
            head,
            LAccess::new(
                O::Vector::unpack(vector),
                O::DistanceAccessor::default_with_dimension(dim),
            ),
        );
        let norm = meta_tuple.centroid_norm();
        let first = meta_tuple.first();
        vec![(Reverse(distance), AlwaysEqual(norm), AlwaysEqual(first))]
    } else {
        // fast path
        trace_vchord_print!("fast path");
        let distance = Distance::ZERO;
        let norm = meta_tuple.centroid_norm();
        let first = meta_tuple.first();
        vec![(Reverse(distance), AlwaysEqual(norm), AlwaysEqual(first))]
    };

    drop(meta_guard);
    let lut = O::Vector::preprocess(vector);

    let mut step = |state: State| {
        let mut results = LinkedVec::<(_, AlwaysEqual<Extra1<'b>>)>::new();
        trace_vchord_print!("this loop will run n times: {}", state.len());
        for (Reverse(dis_f), AlwaysEqual(norm), AlwaysEqual(first)) in state {
            tape::read_h1_tape::<R, _, _>(
                by_next(index, first),
                || O::block_access(&lut.0, is_residual, dis_f.to_f32(), norm),
                |(rough, err), head, norm, first, prefetch| {
                    let lowerbound = Distance::from_f32(rough - err * epsilon);
                    trace_vchord_print!("lowerbound: {}", lowerbound.to_f32());
                    results.push((
                        Reverse(lowerbound),
                        AlwaysEqual(bump.alloc((
                            first,
                            norm,
                            head,
                            BorrowedIter::from_slice(prefetch, |x| bump.alloc_slice(x)),
                        ))),
                    ));
                },
            );
        }
        let mut heap = prefetch_h1_vectors.prefetch(results.into_vec());
        let mut cache = BinaryHeap::<(_, _, _)>::new();
        std::iter::from_fn(move || {
            while let Some(((Reverse(_), AlwaysEqual(&mut (first, norm, head, ..))), prefetch)) =
                heap.next_if(|(d, _)| Some(*d) > cache.peek().map(|(d, ..)| *d))
            {
                let distance = centroids::read::<R, O, _>(
                    prefetch,
                    head,
                    LAccess::new(
                        O::Vector::unpack(vector),
                        O::DistanceAccessor::default_with_dimension(dim),
                    ),
                );
                cache.push((Reverse(distance), AlwaysEqual(norm), AlwaysEqual(first)));
            }
            cache.pop()
        })
    };

    let mut it = None;
    for i in 1..height_of_root {
        trace_vchord_print!(
            "probes[{}]: {}, cells[{}]: {}",
            i - 1,
            probes[i as usize - 1],
            height_of_root - 1 - i,
            cells[(height_of_root - 1 - i) as usize]
        );

        let partial_scan = probes[i as usize - 1] < cells[(height_of_root - 1 - i) as usize];
        let needs_sort = i + 1 == height_of_root && threshold != 0;
        if partial_scan || is_residual || needs_sort {
            let it = it.insert(step(state));
            state = it.take(probes[i as usize - 1] as _).collect();
            trace_vchord_print!("slow path for {}, state.len: {}", i, state.len());
        } else {
            // fast path
            trace_vchord_print!("fast path for {}", i);
            let mut results = LinkedVec::new();
            trace_vchord_print!("this loop will run n times: {}", state.len());
            for (Reverse(_), AlwaysEqual(_), AlwaysEqual(first)) in state {
                tape::read_h1_tape::<R, _, _>(
                    by_next(index, first),
                    || FunctionalAccessor::new((), id_0(|_, _| ()), id_1(|_, _| [(); _])),
                    |(), _, norm, first, _| {
                        results.push((
                            Reverse(Distance::ZERO),
                            AlwaysEqual(norm),
                            AlwaysEqual(first),
                        ));
                    },
                );
            }
            state = results.into_vec();
            trace_vchord_print!("state.len: {}", state.len());
        }
    }

    let mut results = LinkedVec::<(_, AlwaysEqual<_>)>::new();
    trace_vchord_print!("this loop will run n times: {}", state.len());
    for (Reverse(dis_f), AlwaysEqual(norm), AlwaysEqual(first)) in state {
        let jump_guard = index.read(first);
        let jump_bytes = jump_guard.get(1).expect("data corruption");
        let jump_tuple = JumpTuple::deserialize_ref(jump_bytes);
        let mut callback = id_2(|(rough, err), head, payload, prefetch| {
            let lowerbound = Distance::from_f32(rough - err * epsilon);
            let rough = Distance::from_f32(rough);
            trace_vchord_print!(
                "lowerbound: {}, rough: {}",
                lowerbound.to_f32(),
                rough.to_f32()
            );
            results.push((
                (Reverse(lowerbound), AlwaysEqual(rough)),
                AlwaysEqual(PackedRefMut8(bump.alloc((
                    payload,
                    head,
                    BorrowedIter::from_slice(prefetch, |x| bump.alloc_slice(x)),
                )))),
            ));
        });
        if prefetch_h0_tuples.is_not_plain() {
            trace_vchord_print!("prefetch_h0_tuples is not plain");
            let directory =
                tape::read_directory_tape::<R>(by_next(index, jump_tuple.directory_first()));
            tape::read_frozen_tape::<R, _, _>(
                by_directory(&mut prefetch_h0_tuples, directory),
                || O::block_access(&lut.0, is_residual, dis_f.to_f32(), norm),
                &mut callback,
            );
        } else {
            trace_vchord_print!("prefetch_h0_tuples is plain");
            tape::read_frozen_tape::<R, _, _>(
                by_next(index, jump_tuple.frozen_first()),
                || O::block_access(&lut.0, is_residual, dis_f.to_f32(), norm),
                &mut callback,
            );
        }
        tape::read_appendable_tape::<R, _>(
            by_next(index, jump_tuple.appendable_first()),
            O::binary_access(&lut.1, is_residual, dis_f.to_f32(), norm),
            &mut callback,
        );
        threshold = threshold.saturating_sub(jump_tuple.tuples().min(u32::MAX as _) as _);
    }
    let mut estimation_by_threshold = Distance::NEG_INFINITY;
    for (Reverse(distance), AlwaysEqual(_), AlwaysEqual(first)) in it.into_iter().flatten() {
        if threshold == 0 {
            break;
        }
        let jump_guard = index.read(first);
        let jump_bytes = jump_guard.get(1).expect("data corruption");
        let jump_tuple = JumpTuple::deserialize_ref(jump_bytes);
        threshold = threshold.saturating_sub(jump_tuple.tuples().min(u32::MAX as _) as _);
        estimation_by_threshold = distance;
    }
    (results.into_vec(), estimation_by_threshold)
}
