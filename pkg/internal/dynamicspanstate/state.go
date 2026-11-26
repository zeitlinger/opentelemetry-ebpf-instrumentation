// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

// Package dynamicspanstate transports selected dynamic spans with inspected
// processes without adding fields to the public process or service types.
package dynamicspanstate // import "go.opentelemetry.io/obi/pkg/internal/dynamicspanstate"

import (
	"go.opentelemetry.io/obi/internal/config/dynamicspan"
	"go.opentelemetry.io/obi/internal/weakstore"
	"go.opentelemetry.io/obi/pkg/appolly/discover/exec"
)

var spansByFile weakstore.Store[exec.FileInfo, []dynamicspan.Span]

// Set associates spans selected for a process with its inspection snapshot.
func Set(file *exec.FileInfo, spans []dynamicspan.Span) {
	if len(spans) == 0 {
		return
	}
	weakstore.Set(&spansByFile, file, append([]dynamicspan.Span(nil), spans...))
}

// ForFile returns a copy of the spans selected for the inspected process.
func ForFile(file *exec.FileInfo) []dynamicspan.Span {
	spans, _ := weakstore.Get(&spansByFile, file)
	return append([]dynamicspan.Span(nil), spans...)
}
