// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

package dynamicspan // import "go.opentelemetry.io/obi/internal/config/dynamicspan"

import (
	"context"
)

// RulePlan carries config-owned dynamic spans in discovery selector order.
type RulePlan struct {
	Glob  [][]Span
	Regex [][]Span
}

type rulePlanContextKey struct{}

// WithRulePlan attaches an immutable config rule plan to a discovery context.
func WithRulePlan(ctx context.Context, plan RulePlan) context.Context {
	return context.WithValue(ctx, rulePlanContextKey{}, cloneRulePlan(plan))
}

// RulePlanFromContext returns a copy of the config rule plan, if present.
func RulePlanFromContext(ctx context.Context) RulePlan {
	plan, _ := ctx.Value(rulePlanContextKey{}).(RulePlan)
	return cloneRulePlan(plan)
}

func cloneRulePlan(plan RulePlan) RulePlan {
	clone := func(rows [][]Span) [][]Span {
		if rows == nil {
			return nil
		}
		out := make([][]Span, len(rows))
		for i := range rows {
			out[i] = append([]Span(nil), rows[i]...)
		}
		return out
	}
	return RulePlan{Glob: clone(plan.Glob), Regex: clone(plan.Regex)}
}

// Span is runtime-only dynamic span configuration. It intentionally remains
// outside the public configuration and service selector types.
type Span struct {
	Name              string
	FunctionReference string
}
