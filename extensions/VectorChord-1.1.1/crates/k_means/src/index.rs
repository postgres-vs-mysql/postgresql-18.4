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

use crate::This;
use crate::square::{Square, SquareMut};
use rand::RngExt;
use rayon::prelude::*;
use simd::Floating;
use trace::{trace_guard, trace_vchord_print};

pub fn flat_index(centroids: &Square) -> impl Fn(&[f32]) -> (f32, usize) + Sync {
    let _guard = trace_guard!("flat_index [rust]");
    move |sample| {
        let mut result = (f32::INFINITY, 0);
        let mut count = 0;
        for (i, centroid) in centroids.into_iter().enumerate() {
            let dis = f32::reduce_sum_of_d2(sample, centroid);
            trace_vchord_print!("dis: {}, compared value: {}, i: {}", dis, result.0, i);
            if dis <= result.0 {
                result = (dis, i);
                trace_vchord_print!("set result(dis: {}, i: {})", dis, i);
            }
            count = count + 1;
        }
        trace_vchord_print!("centroids compared: {}", count);
        result
    }
}

pub fn rabitq_index(
    pool: &rayon::ThreadPool,
    centroids: &Square,
) -> impl Fn(&[f32]) -> (f32, usize) + Sync {
    let _guard = trace_guard!("rabitq_index [rust]");
    use rabitq::packing::{pack_to_u4, padding_pack};

    trace_vchord_print!("set thread trace mode and begin parallel execution");
    trace::enable_trace_thread_mode();

    let (metadata, blocks) = pool.install(|| {
        let metadata = centroids
            .par_iter()
            .map(rabitq::bit::code_metadata)
            .collect::<Vec<_>>();

        let blocks = centroids
            .par_iter()
            .chunks(32)
            .map(|chunk| {
                let f = |x: &&_| pack_to_u4(&rabitq::bit::code_elements(x));
                padding_pack(chunk.iter().map(f))
            })
            .collect::<Vec<_>>();

        (metadata, blocks)
    });

    trace::disable_trace_thread_mode();
    trace_vchord_print!("parallel execution finished, and process trace mode is now enabled.");

    move |sample| {
        let lut = rabitq::bit::block::preprocess(sample);
        let mut result = (f32::INFINITY, 0);
        let mut sum = [0u32; 32];
        let mut count = 0;
        for (i, centroid) in centroids.into_iter().enumerate() {
            if i % 32 == 0 {
                sum = rabitq::bit::block::accumulate(&blocks[i / 32], &lut.1);
            }
            let (rough, err) =
                rabitq::bit::block::half_process_l2s(sum[i % 32], metadata[i], lut.0);
            let lowerbound = rough - err * 1.9;
            trace_vchord_print!(
                "lowerbound: {}, compared value: {}, i: {}",
                lowerbound,
                result.0,
                i
            );
            if lowerbound < result.0 {
                count = count + 1;
                let dis = f32::reduce_sum_of_d2(sample, centroid);
                if dis <= result.0 {
                    result = (dis, i);
                    trace_vchord_print!("set result(dis: {}, i: {})", dis, i);
                }
            }
        }
        trace_vchord_print!(
            "centroids compared: {}, centroids.len: {}",
            count,
            centroids.len()
        );
        result
    }
}

pub fn update(
    this: &mut This<'_>,
    samples: &SquareMut<'_>,
    targets: &[usize],
    centroids: &mut Square,
) {
    let _guard = trace_guard!("k_means::index::update [rust]");

    trace_vchord_print!("set thread trace mode and begin parallel execution");
    trace::enable_trace_thread_mode();
    this.pool.install(|| {
        const DELTA: f32 = 9.7656e-4_f32;

        let d = this.d;
        let n = samples.len();
        let c = this.c;

        trace_vchord_print!("d: {}, n: {}, c: {}", d, n, c);
        trace_vchord_print!("call rayon::broadcast");
        let list = rayon::broadcast({
            |ctx| {
                let mut sum = Square::from_zeros(d, c);
                let mut count = vec![0.0f32; c];
                trace_vchord_print!("num_threads: {}", ctx.num_threads());
                for i in (ctx.index()..samples.len()).step_by(ctx.num_threads()) {
                    let target = targets[i];
                    let sample = &samples[i];
                    f32::vector_add_inplace(&mut sum[target], sample);
                    count[target] += 1.0;
                }
                (sum, count)
            }
        });
        let mut sum = Square::from_zeros(d, c);
        let mut count = vec![0.0f32; c];

        trace_vchord_print!("process the list sum and count");
        for (sum_1, count_1) in list {
            for i in 0..c {
                f32::vector_add_inplace(&mut sum[i], &sum_1[i]);
                count[i] += count_1[i];
            }
        }

        trace_vchord_print!("in-place parallel computation");
        sum.par_iter_mut()
            .zip(count.par_iter())
            .for_each(|(sum, count)| f32::vector_mul_scalar_inplace(sum, 1.0 / count));

        trace_vchord_print!("in-place parallel computation over");
        *centroids = sum;

        trace_vchord_print!("process the loop (counts: {})", c);
        for i in 0..c {
            if count[i] != 0.0f32 {
                continue;
            }
            let mut o = 0;
            loop {
                let alpha = this.rng.random_range(0.0..1.0f32);
                let beta = (count[o] - 1.0) / (n - c) as f32;
                if alpha < beta {
                    break;
                }
                o = (o + 1) % c;
            }
            centroids.copy_within(o..o + 1, i);
            vector_mul_scalars_inplace(&mut centroids[i], [1.0 + DELTA, 1.0 - DELTA]);
            vector_mul_scalars_inplace(&mut centroids[o], [1.0 - DELTA, 1.0 + DELTA]);
            count[i] = count[o] / 2.0;
            count[o] -= count[i];
        }

        trace_vchord_print!("process the loop (counts: {}) over", c);
        if this.is_spherical {
            trace_vchord_print!("when is_spherical is true, do in-place parallel computation");
            centroids.into_par_iter().for_each(|centroid| {
                let l = f32::reduce_sum_of_x2(centroid).sqrt();
                f32::vector_mul_scalar_inplace(centroid, 1.0 / l);
            });
        }
    });

    trace::disable_trace_thread_mode();
    trace_vchord_print!("parallel execution finished, and process trace mode is now enabled.");
}

fn vector_mul_scalars_inplace(this: &mut [f32], scalars: [f32; 2]) {
    let _guard = trace_guard!("vector_mul_scalars_inplace [rust]");
    let n: usize = this.len();
    for i in 0..n {
        if i % 2 == 0 {
            this[i] *= scalars[0];
        } else {
            this[i] *= scalars[1];
        }
    }
}
