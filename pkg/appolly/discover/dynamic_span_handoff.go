// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

package discover // import "go.opentelemetry.io/obi/pkg/appolly/discover"

import (
	"sync"

	"go.opentelemetry.io/obi/internal/config/dynamicspan"
	"go.opentelemetry.io/obi/pkg/ebpf"
)

type dynamicSpanTarget struct {
	spans         []dynamicspan.Span
	update        bool
	samplerUpdate bool
}

// dynamicSpanHandoff keeps each desired snapshot attached to the exact event
// that produced it while it crosses the discovery pipeline.
type dynamicSpanHandoff struct {
	mu      sync.Mutex
	matches map[*ProcessMatch]dynamicSpanTarget
	files   map[*ebpf.Instrumentable]dynamicSpanTarget
}

func newDynamicSpanHandoff() *dynamicSpanHandoff {
	return &dynamicSpanHandoff{
		matches: map[*ProcessMatch]dynamicSpanTarget{},
		files:   map[*ebpf.Instrumentable]dynamicSpanTarget{},
	}
}

func (h *dynamicSpanHandoff) putMatch(match *ProcessMatch, spans []dynamicspan.Span, update, samplerUpdate bool) {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.matches[match] = dynamicSpanTarget{
		spans: append([]dynamicspan.Span(nil), spans...), update: update, samplerUpdate: samplerUpdate,
	}
}

func (h *dynamicSpanHandoff) takeMatch(match *ProcessMatch) (dynamicSpanTarget, bool) {
	h.mu.Lock()
	defer h.mu.Unlock()
	target, ok := h.matches[match]
	delete(h.matches, match)
	return target, ok
}

func (h *dynamicSpanHandoff) putInstrumentable(instrumentable *ebpf.Instrumentable, target dynamicSpanTarget) {
	h.mu.Lock()
	defer h.mu.Unlock()
	target.spans = append([]dynamicspan.Span(nil), target.spans...)
	h.files[instrumentable] = target
}

func (h *dynamicSpanHandoff) takeInstrumentable(instrumentable *ebpf.Instrumentable) (dynamicSpanTarget, bool) {
	h.mu.Lock()
	defer h.mu.Unlock()
	target, ok := h.files[instrumentable]
	delete(h.files, instrumentable)
	return target, ok
}
