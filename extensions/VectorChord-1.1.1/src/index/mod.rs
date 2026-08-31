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

mod fetcher;
mod functions;
mod gucs;
mod hook;
mod opclass;
mod sample;
mod scanners;
mod storage;
mod traverse;
mod vchordg;
mod vchordrq;
use trace::trace_guard;

pub fn init() {
    let _guard = trace_guard!("index::mod::init [rust]");
    gucs::init();
    hook::init();
    vchordrq::am::init();
    vchordg::am::init();
}
