// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

package configload // import "go.opentelemetry.io/obi/cmd/obi/internal/configload"

import (
	"fmt"

	"go.opentelemetry.io/obi/internal/config/convert"
	"go.opentelemetry.io/obi/internal/config/dynamicspan"
	"go.opentelemetry.io/obi/internal/config/schema"
	obicfg "go.opentelemetry.io/obi/pkg/config"
	"go.opentelemetry.io/obi/pkg/obi"
)

// LoadV2 expands environment variables and converts a standalone v2 document.
// Runtime validation is left to the startup or refresh caller.
func LoadV2(data []byte) (*obi.Config, error) {
	cfg, _, err := LoadV2WithRulePlan(data)
	return cfg, err
}

// LoadV2WithRulePlan loads config v2 and preserves its ordered span metadata.
func LoadV2WithRulePlan(data []byte) (*obi.Config, dynamicspan.RulePlan, error) {
	doc, _, err := schema.ParseStandaloneYAML(obicfg.ReplaceEnv(data))
	if err != nil {
		return nil, dynamicspan.RulePlan{}, fmt.Errorf("loading config v2: %w", err)
	}
	cfg, plan, err := convert.DocumentToRuntimeWithRulePlan(doc)
	if err != nil {
		return nil, dynamicspan.RulePlan{}, fmt.Errorf("loading config v2: %w", err)
	}
	return cfg, plan, nil
}
