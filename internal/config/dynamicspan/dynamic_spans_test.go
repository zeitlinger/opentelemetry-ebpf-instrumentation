// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

package dynamicspan

import (
	"context"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestRulePlanContextCopiesOrderedRows(t *testing.T) {
	plan := RulePlan{
		Glob:  [][]Span{{{Name: "first"}}, nil, {{Name: "third"}}},
		Regex: [][]Span{{{Name: "regex"}}},
	}
	ctx := WithRulePlan(context.Background(), plan)
	plan.Glob[0][0].Name = "mutated input"
	got := RulePlanFromContext(ctx)
	require.Equal(t, "first", got.Glob[0][0].Name)
	require.Len(t, got.Glob, 3)
	require.Empty(t, got.Glob[1])
	got.Regex[0][0].Name = "mutated output"
	require.Equal(t, "regex", RulePlanFromContext(ctx).Regex[0][0].Name)
}

func TestValidateV2(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name    string
		spans   []V2SpanTarget
		wantErr string
	}{
		{
			name: "empty declarations",
		},
		{
			name:  "valid declaration without language filter",
			spans: []V2SpanTarget{{Function: "com.example.Service#run"}},
		},
		{
			name:  "malformed selector deferred to runtime",
			spans: []V2SpanTarget{{Function: "com.example.Service#"}},
		},
		{
			name:    "unsupported target",
			spans:   []V2SpanTarget{{FunctionNoRet: "com.example.Service#run"}},
			wantErr: ".on.function is the only currently supported Java span target",
		},
		{
			name:    "attributes",
			spans:   []V2SpanTarget{{Function: "com.example.Service#run", HasAttributes: true}},
			wantErr: ".attributes and automatic_attributes are not currently supported",
		},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			err := ValidateV2(0, test.spans)
			if test.wantErr == "" && err != nil {
				t.Fatalf("ValidateV2() error = %v", err)
			}
			if test.wantErr != "" && (err == nil || !strings.Contains(err.Error(), test.wantErr)) {
				t.Fatalf("ValidateV2() error = %v, want contains %q", err, test.wantErr)
			}
		})
	}
}
