// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

package schemacheck

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

const (
	registryDir = "../../schemas/obi"

	resolveTimeout = 2 * time.Minute
)

type resolvedGroup struct {
	ID         string `json:"id"`
	MetricName string `json:"metric_name"`
}

type resolveOutput struct {
	Groups   []resolvedGroup `json:"groups"`
	Registry struct {
		Groups []resolvedGroup `json:"groups"`
	} `json:"registry"`
}

func (o resolveOutput) groups() []resolvedGroup {
	if len(o.Groups) > 0 {
		return o.Groups
	}
	return o.Registry.Groups
}

// resolveRegistry runs the pinned Mise-managed `weaver` CLI and returns the
// resolved groups. If the CLI is missing, it skips locally and fails in CI.
func resolveRegistry(t *testing.T) resolveOutput {
	t.Helper()
	if testing.Short() {
		t.Skip("provenance check skipped in -short mode; run `mise run test-schema`")
	}
	if _, err := exec.LookPath("weaver"); err != nil {
		if os.Getenv("CI") != "" {
			t.Fatalf("weaver is required for the provenance check in CI: %v", err)
		}
		t.Skipf("weaver is not installed (%v); run `mise install`", err)
	}
	// Without the pinned upstream registry weaver cannot resolve, and the
	// failure says nothing about the registry under test. Skip as the drift
	// tests do, but fail closed in CI where the fetch is part of the target.
	if _, err := os.Stat(upstreamDeps); os.IsNotExist(err) {
		if os.Getenv("CI") != "" {
			t.Fatalf("%s is required for the provenance check in CI; run `mise run fetch-upstream-semconv`", upstreamDeps)
		}
		t.Skipf("%s is not populated; run `mise run fetch-upstream-semconv`", upstreamDeps)
	}
	registryAbs, err := filepath.Abs(registryDir)
	require.NoError(t, err)

	ctx, cancel := context.WithTimeout(t.Context(), resolveTimeout)
	defer cancel()

	cmd := exec.CommandContext(ctx, "weaver", "registry", "resolve", "--registry", registryAbs, "--format", "json")
	cmd.Dir = registryAbs

	// weaver exits non-zero whenever diagnostics exist (e.g. the expected
	// definition/2 UnstableFileFormat warnings), yet still writes the resolved
	// registry JSON to stdout. Parse stdout regardless of the exit code, and
	// treat the run as unavailable only when there is no JSON to parse.
	out, err := cmd.Output()

	var res resolveOutput
	if jsonErr := json.Unmarshal(out, &res); jsonErr != nil {
		var stderr []byte
		if exitErr, ok := errors.AsType[*exec.ExitError](err); ok {
			stderr = exitErr.Stderr
		}
		require.NoErrorf(t, jsonErr,
			"weaver resolve produced no parseable registry JSON (run error: %v)\n%s\n"+
				"the provenance check cannot be skipped once the runtime is present",
			err, stderr)
	}
	require.NotEmpty(t, res.groups(), "weaver resolve returned no groups")
	return res
}

// TestOBIMetricOverridesResolveToLocalNarrowedDefinition verifies that every
// metric marked with annotations.obi.upstream_override resolves to OBI's own
// narrowed group rather than the broader upstream definition. Unreferenced
// upstream metric groups drop from resolution, leaving exactly one group per
// shared metric_name: OBI's. This is what makes the coverage denominator
// reflect OBI's true OTLP contract.
func TestOBIMetricOverridesResolveToLocalNarrowedDefinition(t *testing.T) {
	overrides := overrideMetrics(t)
	require.NotEmpty(t, overrides)

	byName := map[string][]resolvedGroup{}
	for _, g := range resolveRegistry(t).groups() {
		if g.MetricName != "" {
			byName[g.MetricName] = append(byName[g.MetricName], g)
		}
	}

	for name := range overrides {
		groups := byName[name]
		require.Lenf(t, groups, 1,
			"metric %q should resolve to exactly one group without --include-unreferenced, got %d: %v",
			name, len(groups), groups)
		assert.Truef(t, strings.HasPrefix(groups[0].ID, "metric.obi."),
			"metric %q resolves to group %q; expected OBI's narrowed local group (metric.obi.*), not the upstream definition",
			name, groups[0].ID)
	}
}
