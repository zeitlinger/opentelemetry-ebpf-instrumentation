// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

// Package weakstore associates values with object identities without keeping
// those objects alive.
package weakstore // import "go.opentelemetry.io/obi/internal/weakstore"

import (
	"runtime"
	"sync"
	"weak"
)

type Store[K, V any] struct {
	mu     sync.RWMutex
	values map[weak.Pointer[K]]V
}

type cleanupArg[K, V any] struct {
	store *Store[K, V]
	key   weak.Pointer[K]
}

func cleanup[K, V any](arg cleanupArg[K, V]) {
	arg.store.mu.Lock()
	delete(arg.store.values, arg.key)
	arg.store.mu.Unlock()
}

// Set associates value with key. Values must not retain key.
func Set[K, V any](store *Store[K, V], key *K, value V) {
	weakKey := weak.Make(key)
	store.mu.Lock()
	if store.values == nil {
		store.values = make(map[weak.Pointer[K]]V)
	}
	store.values[weakKey] = value
	store.mu.Unlock()
	runtime.AddCleanup(key, cleanup[K, V], cleanupArg[K, V]{store: store, key: weakKey})
}

// Get returns the value associated with key, if present.
func Get[K, V any](store *Store[K, V], key *K) (V, bool) {
	weakKey := weak.Make(key)
	store.mu.RLock()
	value, ok := store.values[weakKey]
	store.mu.RUnlock()
	runtime.KeepAlive(key)
	return value, ok
}
