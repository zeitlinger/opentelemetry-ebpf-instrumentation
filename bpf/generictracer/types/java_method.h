// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

#pragma once

#include <bpfcore/vmlinux.h>

#include <common/tp_info.h>

typedef struct java_method_event {
    u8 type;
    u8 _pad[7];
    u64 start_ns;
    u64 end_ns;
    u32 global_pid;
    u32 global_tid;
    u32 ns_pid;
    u32 ns_tid;
    u32 pid_ns_id;
    u32 method_id;
    u8 trace_id[TRACE_ID_SIZE_BYTES];
    u8 span_id[SPAN_ID_SIZE_BYTES];
    u8 parent_span_id[SPAN_ID_SIZE_BYTES];
    u8 trace_flags;
    u8 exceptional;
    u8 _pad2[6];
} java_method_event_t;
