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

use crate::index::{flat_index as prefect_index, rabitq_index as index};
use crate::square::{Square, SquareMut};
use crate::{KMeans, This};
use rand::rngs::StdRng;
use rand::{RngExt, SeedableRng};
use rayon::prelude::*;
use trace::{trace_guard, trace_vchord_print};

struct RaBitQ<'a> {
    this: This<'a>,
    samples: SquareMut<'a>,
    centroids: Square,
    targets: Vec<usize>,
}

impl<'a> KMeans for RaBitQ<'a> {
    fn prefect_index(&self) -> Box<dyn Fn(&[f32]) -> (f32, usize) + Sync + '_> {
        let _guard = trace_guard!("KMeans(RaBitQ)::prefect_index [rust]");
        let index = prefect_index(&self.centroids);
        Box::new(move |sample| {
            let rotated = rabitq::rotate::rotate(sample);
            let sample = rotated.as_slice();
            index(sample)
        })
    }

    fn index(&self) -> Box<dyn Fn(&[f32]) -> (f32, usize) + Sync + '_> {
        let _guard = trace_guard!("KMeans(RaBitQ)::index [rust]");
        let index = index(self.this.pool, &self.centroids);
        Box::new(move |sample| {
            let rotated = rabitq::rotate::rotate(sample);
            let sample = rotated.as_slice();
            index(sample)
        })
    }

    fn assign(&mut self) {
        let this = &mut self.this;
        let samples = &mut self.samples;
        let centroids = &self.centroids;
        let targets = &mut self.targets;
        let index = index(this.pool, centroids);

        let _guard = trace_guard!("KMeans(RaBitQ)::assign [rust]");

        let total = targets.len();
        let trace_enable_flag = trace::trace_enabled();
        let max_trace_iterations = trace::max_trace_iterations() as usize;
        trace_vchord_print!("targets.len: {}", total);
        trace_vchord_print!("set thread trace mode and begin parallel execution");
        trace::enable_trace_thread_mode();

        this.pool.install(|| {
            targets
                .par_iter_mut()
                .zip(samples.par_iter_mut())
                .enumerate()
                .for_each(|(idx, (target, sample))| {
                    if idx >= max_trace_iterations {
                        trace_vchord_print!(
                            "temporarily disable tracing during parallel processing in rust"
                        );
                        if trace_enable_flag {
                            if idx + 1 == total {
                                trace::enable_trace();
                                if total != max_trace_iterations {
                                    trace_vchord_print!("...");
                                }
                            } else if idx == max_trace_iterations {
                                trace::disable_trace();
                            }
                        }
                    }
                    trace_vchord_print!("idx: {}", idx);
                    *target = index(sample).1;
                });

            if total > max_trace_iterations {
                trace_vchord_print!("total processed: {}", total);
            }
        });

        trace::disable_trace_thread_mode();
        trace_vchord_print!("parallel execution finished, and process trace mode is now enabled.");
    }

    fn update(&mut self) {
        let _guard = trace_guard!("KMeans(RaBitQ)::update [rust]");
        crate::index::update(
            &mut self.this,
            &self.samples,
            &self.targets,
            &mut self.centroids,
        );
    }

    fn finish(mut self: Box<Self>) -> Square {
        let _guard = trace_guard!("KMeans(RaBitQ)::finish [rust]");
        trace_vchord_print!("set thread trace mode and begin parallel execution");
        trace::enable_trace_thread_mode();
        self.this.pool.install(|| {
            self.centroids.par_iter_mut().for_each(|centroid| {
                rabitq::rotate::rotate_reversed_inplace(centroid);
            });
        });
        trace::disable_trace_thread_mode();
        trace_vchord_print!("parallel execution finished, and process trace mode is now enabled.");
        trace_vchord_print!("centroids.len: {}", self.centroids.len());
        self.centroids
    }
}

pub fn new<'a>(
    pool: &'a rayon::ThreadPool,
    d: usize,
    mut samples: SquareMut<'a>,
    c: usize,
    seed: [u8; 32],
    is_spherical: bool,
) -> Box<dyn KMeans + 'a> {
    let _guard = trace_guard!("k_means::rabitq::new [rust]");
    let mut rng = StdRng::from_seed(seed);

    trace_vchord_print!("set thread trace mode and begin parallel execution");
    trace::enable_trace_thread_mode();

    pool.install(|| {
        samples.par_iter_mut().for_each(|sample| {
            rabitq::rotate::rotate_inplace(sample);
        });
    });

    trace::disable_trace_thread_mode();
    trace_vchord_print!("parallel execution finished, and process trace mode is now enabled.");

    let mut centroids = Square::with_capacity(d, c);

    for index in rand::seq::index::sample(&mut rng, samples.len(), c.min(samples.len())) {
        centroids.push_slice(&samples[index]);
    }

    if centroids.is_empty() && c == 1 {
        centroids.push_iter(std::iter::repeat_n(0.0, d as _));
    }

    while centroids.len() < c {
        centroids.push_iter((0..d).map(|_| rng.random_range(-1.0f32..1.0f32)));
    }

    trace_vchord_print!("set thread trace mode and begin parallel execution");
    trace::enable_trace_thread_mode();
    pool.install(|| {
        if is_spherical {
            use simd::Floating;
            (&mut centroids).into_par_iter().for_each(|centroid| {
                let l = f32::reduce_sum_of_x2(centroid).sqrt();
                f32::vector_mul_scalar_inplace(centroid, 1.0 / l);
            });
        }
    });

    trace::disable_trace_thread_mode();
    trace_vchord_print!("parallel execution finished, and process trace mode is now enabled.");

    let targets = vec![0; samples.len()];

    Box::new(RaBitQ {
        this: This {
            pool,
            d,
            c,
            rng,
            is_spherical,
        },
        samples,
        centroids,
        targets,
    })
}
