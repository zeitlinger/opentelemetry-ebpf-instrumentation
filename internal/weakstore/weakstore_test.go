// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

package weakstore

import (
	"runtime"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

type testKey struct{ value [3]int }

func TestStoreTracksObjectIdentityAndCleansCollectedKeys(t *testing.T) {
	var store Store[testKey, string]
	other := &testKey{value: [3]int{1, 2, 3}}
	_, ok := Get(&store, other)
	require.False(t, ok)

	func() {
		key := &testKey{value: [3]int{1, 2, 3}}
		require.Equal(t, [3]int{1, 2, 3}, key.value)
		Set(&store, key, "one")
		value, found := Get(&store, key)
		require.True(t, found)
		require.Equal(t, "one", value)
	}()

	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		runtime.GC()
		store.mu.RLock()
		remaining := len(store.values)
		store.mu.RUnlock()
		if remaining == 0 {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatal("weak-key entry was not cleaned up")
}
