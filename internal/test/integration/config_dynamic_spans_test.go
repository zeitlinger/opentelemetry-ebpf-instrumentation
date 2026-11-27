// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

package integration

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/moby/moby/client"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"go.opentelemetry.io/obi/internal/test/integration/components/docker"
	"go.opentelemetry.io/obi/internal/test/integration/components/jaeger"
	ti "go.opentelemetry.io/obi/pkg/test/integration"
)

const (
	dynamicSpansJavaServer  = "http://localhost:18080"
	dynamicSpansNodeServer  = "http://localhost:18090"
	dynamicSpanPollInterval = 100 * time.Millisecond
	dynamicSpanSettleWindow = 2 * time.Second
)

func TestConfigDynamicSpansReload(t *testing.T) {
	initial, err := os.ReadFile("configs/obi-config-dynamic-spans-v2.yml")
	require.NoError(t, err)
	configDir := t.TempDir()
	configPath := filepath.Join(configDir, "obi.yml")
	replaceReloadConfig(t, configPath, initial)

	compose, err := docker.ComposeSuite("docker-compose-config-dynamic-spans.yml",
		filepath.Join(pathOutput, "test-suite-config-dynamic-spans.log"))
	require.NoError(t, err)
	compose.Env = append(compose.Env,
		"CONFIG_RELOAD_DIR="+configDir,
		"JAVA_HTTPCLIENT_RUNTIME_IMAGE=gradle:9.8.2-jdk21-noble@sha256:1278203f5f52e4781e6d7096250375a4d54ab599f26e5ba44e672b4bdbd793f7",
	)
	t.Cleanup(func() { assert.NoError(t, compose.Close()) })
	require.NoError(t, compose.Up())

	httpClient := &http.Client{Timeout: 30 * time.Second}
	t.Cleanup(httpClient.CloseIdleConnections)
	require.EventuallyWithT(t, func(ct *assert.CollectT) {
		ti.DoHTTPGetWithClient(ct, httpClient, dynamicSpansJavaServer+"/health", http.StatusOK)
		ti.DoHTTPGetWithClient(ct, httpClient, dynamicSpansNodeServer+"/ready", http.StatusOK)
	}, testTimeout, 250*time.Millisecond)

	cl, err := client.New(client.FromEnv)
	require.NoError(t, err)
	defer cl.Close()
	obiID := testContainerID(t, cl, "hatest-obi-dynamic-spans")
	require.NotEmpty(t, obiID)
	obiBefore, err := cl.ContainerInspect(t.Context(), obiID, client.ContainerInspectOptions{})
	require.NoError(t, err)
	workloadIDs := map[string]uint64{
		"java": reloadServerPID(t, compose, "java"),
		"node": reloadServerPID(t, compose, "node"),
	}
	workloadStarts := map[string]string{}
	for _, service := range []string{"java", "node"} {
		id := testContainerID(t, cl, "hatest-"+service+"-dynamic-spans")
		require.NotEmpty(t, id)
		info, inspectErr := cl.ContainerInspect(t.Context(), id, client.ContainerInspectOptions{})
		require.NoError(t, inspectErr)
		workloadStarts[service] = info.Container.State.StartedAt
	}

	for _, workload := range dynamicSpanWorkloads {
		waitDynamicSpanTrace(t, httpClient, workload, "initial", map[string]int{
			workload.firstName:  0,
			workload.secondName: 0,
		})
	}

	t.Log("add Java and Node.js function spans to the existing processes")
	replaceReloadConfig(t, configPath, dynamicSpanConfig(initial, "first"))
	for _, workload := range dynamicSpanWorkloads {
		waitDynamicSpanTrace(t, httpClient, workload, "added", map[string]int{workload.firstName: 1})
	}

	t.Log("apply the same rules again and ensure the existing wrappers do not duplicate spans")
	repeated := append(dynamicSpanConfig(initial, "first"), []byte("# redeliver identical dynamic spans\n")...)
	replaceReloadConfig(t, configPath, repeated)
	for _, workload := range dynamicSpanWorkloads {
		waitDynamicSpanTrace(t, httpClient, workload, "repeated", map[string]int{workload.firstName: 1})
	}

	t.Log("replace the configured span names while retaining each target")
	replaceReloadConfig(t, configPath, dynamicSpanConfig(initial, "second"))
	for _, workload := range dynamicSpanWorkloads {
		waitDynamicSpanTrace(t, httpClient, workload, "replaced", map[string]int{
			workload.firstName:  0,
			workload.secondName: 1,
		})
	}

	t.Log("clear the dynamic spans")
	replaceReloadConfig(t, configPath, initial)
	for _, workload := range dynamicSpanWorkloads {
		waitDynamicSpanTrace(t, httpClient, workload, "cleared", map[string]int{
			workload.firstName:  0,
			workload.secondName: 0,
		})
	}

	for service, pid := range workloadIDs {
		assert.Equal(t, pid, reloadServerPID(t, compose, service), "%s process PID changed", service)
		id := testContainerID(t, cl, "hatest-"+service+"-dynamic-spans")
		info, inspectErr := cl.ContainerInspect(t.Context(), id, client.ContainerInspectOptions{})
		require.NoError(t, inspectErr)
		assert.Equal(t, workloadStarts[service], info.Container.State.StartedAt, "%s process container restarted", service)
		assert.True(t, info.Container.State.Running)
		assert.Zero(t, info.Container.RestartCount)
	}
	obiAfter, err := cl.ContainerInspect(t.Context(), obiID, client.ContainerInspectOptions{})
	require.NoError(t, err)
	assert.Equal(t, obiBefore.Container.State.StartedAt, obiAfter.Container.State.StartedAt)
	assert.True(t, obiAfter.Container.State.Running)
	assert.Zero(t, obiAfter.Container.RestartCount)
}

type dynamicSpanWorkload struct {
	service, port, firstName, secondName string
	path                                 func(string) string
}

var dynamicSpanWorkloads = []dynamicSpanWorkload{
	{
		service: "dynamic-java", port: dynamicSpansJavaServer,
		firstName: "dynamic.java.first", secondName: "dynamic.java.second",
		path: func(id string) string { return "/call/" + id },
	},
	{
		service: "dynamic-node", port: dynamicSpansNodeServer,
		firstName: "dynamic.node.first", secondName: "dynamic.node.second",
		path: func(id string) string { return "/invoke/" + id },
	},
}

func dynamicSpanConfig(base []byte, version string) []byte {
	names := map[string]string{}
	if version != "" {
		names["java"] = "dynamic.java." + version
		names["node"] = "dynamic.node." + version
	}
	config := string(base)
	for language, port := range map[string]string{"java": "8080", "node": "3030"} {
		if name, ok := names[language]; ok {
			function := "Main.call"
			if language == "node" {
				function = "**/app.js:exports.selected"
			}
			replacement := fmt.Sprintf("open_ports: \"%s\"\n          refine:\n            spans/development:\n              - name: %s\n                on:\n                  function: %s", port, name, function)
			config = strings.Replace(config, "open_ports: \""+port+"\"", replacement, 1)
		}
	}
	return []byte(config)
}

func waitDynamicSpanTrace(t *testing.T, httpClient *http.Client, workload dynamicSpanWorkload, marker string, expected map[string]int) {
	t.Helper()
	attempt := 0
	require.EventuallyWithT(t, func(ct *assert.CollectT) {
		attempt++
		path := workload.path(fmt.Sprintf("%s-%d", marker, attempt))
		start := time.Now().Truncate(time.Millisecond)
		ti.DoHTTPGetWithClient(ct, httpClient, workload.port+path, http.StatusOK)
		require.EventuallyWithT(ct, func(traceCT *assert.CollectT) {
			trace, err := dynamicSpanTrace(workload.service, path)
			require.NoError(traceCT, err)
			require.NotEmpty(traceCT, trace.TraceID, "no HTTP trace for %s", path)
		}, 10*time.Second, dynamicSpanPollInterval)

		for name, count := range expected {
			if count == 0 {
				continue
			}
			require.EventuallyWithT(ct, func(spanCT *assert.CollectT) {
				actual, queryErr := dynamicSpanCountSince(workload.service, name, start)
				require.NoError(spanCT, queryErr)
				assert.Equal(spanCT, count, actual, "unexpected number of %q spans since invocation", name)
			}, 5*time.Second, dynamicSpanPollInterval)
		}

		var queryErr error
		require.Never(ct, func() bool {
			for name, count := range expected {
				actual, err := dynamicSpanCountSince(workload.service, name, start)
				if err != nil {
					queryErr = err
					return true
				}
				if actual != count {
					return true
				}
			}
			return false
		}, dynamicSpanSettleWindow, dynamicSpanPollInterval, "dynamic span counts changed after they settled")
		require.NoError(ct, queryErr)
	}, testTimeout, 250*time.Millisecond)
}

func dynamicSpanTrace(service, path string) (jaeger.Trace, error) {
	return latestTraceMatching(service, func(trace jaeger.Trace) bool {
		return traceHasSpanTags(trace,
			jaeger.Tag{Key: "url.path", Type: "string", Value: path},
			jaeger.Tag{Key: "span.kind", Type: "string", Value: "server"},
		)
	})
}

func dynamicSpanCountSince(service, operation string, start time.Time) (int, error) {
	params := url.Values{
		"service":   {service},
		"operation": {operation},
		"start":     {strconv.FormatInt(start.UnixMicro(), 10)},
		"end":       {strconv.FormatInt(time.Now().UnixMicro(), 10)},
		"limit":     {"1000"},
	}
	resp, err := getJaeger(jaegerQueryURL + "?" + params.Encode())
	if err != nil {
		return 0, err
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode != http.StatusOK {
		return 0, fmt.Errorf("Jaeger query for %s returned status %d", operation, resp.StatusCode)
	}
	var query jaeger.TracesQuery
	if err := json.NewDecoder(resp.Body).Decode(&query); err != nil {
		return 0, err
	}
	var count int
	for _, trace := range query.Data {
		for _, span := range trace.Spans {
			if span.OperationName == operation {
				count++
			}
		}
	}
	return count, nil
}
