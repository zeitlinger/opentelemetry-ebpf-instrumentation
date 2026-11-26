// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

package dynamicspan // import "go.opentelemetry.io/obi/internal/config/dynamicspan"

import (
	"go.opentelemetry.io/obi/internal/weakstore"
	"go.opentelemetry.io/obi/pkg/appolly/services"
)

// Span is runtime-only dynamic span configuration. It intentionally remains
// outside the public configuration and service selector types.
type Span struct {
	Name              string
	FunctionReference string
}

var (
	globSelectorSpans  weakstore.Store[services.GlobAttributes, []Span]
	regexSelectorSpans weakstore.Store[services.RegexSelector, []Span]
)

// RegisterSelector associates spans with the final selector slice element.
func RegisterSelector(selector services.Selector, spans []Span) {
	if len(spans) == 0 {
		return
	}
	spans = append([]Span(nil), spans...)
	switch selector := selector.(type) {
	case *services.GlobAttributes:
		weakstore.Set(&globSelectorSpans, selector, spans)
	case *services.RegexSelector:
		weakstore.Set(&regexSelectorSpans, selector, spans)
	}
}

// ForSelector returns a copy of the dynamic spans registered for selector.
func ForSelector(selector services.Selector) []Span {
	var spans []Span
	switch selector := selector.(type) {
	case *services.GlobAttributes:
		spans, _ = weakstore.Get(&globSelectorSpans, selector)
	case *services.RegexSelector:
		spans, _ = weakstore.Get(&regexSelectorSpans, selector)
	}
	return append([]Span(nil), spans...)
}

// CopySelectorRegistration copies a selector sidecar when a selector value is
// cloned into another backing slice.
func CopySelectorRegistration(from, to services.Selector) {
	switch from := from.(type) {
	case *services.GlobAttributes:
		to, ok := to.(*services.GlobAttributes)
		if spans, found := weakstore.Get(&globSelectorSpans, from); found && ok {
			weakstore.Set(&globSelectorSpans, to, spans)
		}
	case *services.RegexSelector:
		to, ok := to.(*services.RegexSelector)
		if spans, found := weakstore.Get(&regexSelectorSpans, from); found && ok {
			weakstore.Set(&regexSelectorSpans, to, spans)
		}
	}
}
