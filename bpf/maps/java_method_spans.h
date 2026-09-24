// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

#pragma once

#include <bpfcore/vmlinux.h>
#include <bpfcore/bpf_helpers.h>

#include <common/tp_info.h>
#include <common/pin_internal.h>

enum { k_java_method_span_max_depth = 4 };

typedef struct java_method_frame {
    tp_info_t tp;
    u32 method_id;
    u32 _pad;
} java_method_frame_t;

typedef struct java_method_stack {
    u32 depth;
    u32 overflow_depth;
    java_method_frame_t frames[k_java_method_span_max_depth];
} java_method_stack_t;

struct {
    __uint(type, BPF_MAP_TYPE_HASH);
    __type(key, u64);
    __type(value, java_method_stack_t);
    __uint(max_entries, 1 << 14);
    __uint(pinning, OBI_PIN_INTERNAL);
} java_method_spans SEC(".maps");

// Scratch task-context snapshot keyed by (process ID, task identity hash).
// This supports the async propagation experiment only; identity hashes are
// not collision-free production task identifiers.
struct {
    __uint(type, BPF_MAP_TYPE_LRU_HASH);
    __type(key, u64);
    __type(value, java_method_stack_t);
    __uint(max_entries, 1 << 14);
    __uint(pinning, OBI_PIN_INTERNAL);
} java_method_task_contexts SEC(".maps");

// Scratch restoration state keyed by worker pid_tgid. The prototype supports
// one active task scope per worker and is not a general nested-scope stack.
struct {
    __uint(type, BPF_MAP_TYPE_HASH);
    __type(key, u64);
    __type(value, java_method_stack_t);
    __uint(max_entries, 1 << 14);
    __uint(pinning, OBI_PIN_INTERNAL);
} java_method_task_backups SEC(".maps");
