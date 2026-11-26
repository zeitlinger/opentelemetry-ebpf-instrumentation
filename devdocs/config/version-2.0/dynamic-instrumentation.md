# Config v2 dynamic instrumentation

← [Config v2 reference](config-v2.md)

Experimental dynamic span declarations are configured per capture rule under
`capture.rules[].refine.spans/development`. A non-empty list on an include
rule opts in; an omitted or empty list leaves dynamic spans off. This experimental
setting keeps each declaration alongside the workload selection it refines.
This is startup-only: any configuration refresh while experimental spans are
configured in either the current or next configuration requires restarting OBI.
A span has a name, exactly one target under
`on`, and optional `attributes` mappings. The schema reserves the target keys
`function`, `function_noret`, `usdt`, and `usdt_noret`; currently, the Java and
Node.js runtime adapters accept only `on.function`. They do not support explicit
attributes or automatic attribute capture. `function_noret` and both USDT forms
are reserved schema shapes, not runtime-supported targets. No Go runtime
implementation is in scope for this experimental feature.

`function` and `function_noret` identify function targets; `usdt` and
`usdt_noret` identify USDT targets. The key selects the target family and
variant; target values must be non-empty strings. `function` is an opaque
runtime-specific reference. `function_noret` is a function symbol or glob for
an entry-only, zero-duration marker; its concrete symbol/glob syntax is defined
by each runtime adapter. `usdt` uses `provider:base` to identify paired
`<base>_start` and `<base>_end` probes. `usdt_noret` uses `provider:name` to
identify one zero-duration marker probe. `on.match` is valid only with a USDT
target and filters by equality against the selected string-valued argument.
The shared schema describes these reserved forms but does not imply runtime
support. Capture selectors continue to use the semantics of the corresponding
Config v2 selector; they do not change target-value syntax.

Function selectors should be as simple as possible: start with the target
information you know, then add qualifiers only when the selector matches more
functions than intended. Discovery, globbing, and available qualifiers are
runtime-specific; consult the runtime reference before relying on them.

A `function` span measures one function invocation: it ends when the function
returns or throws. If the function starts asynchronous work and returns before
that work completes, the function span does not extend to the asynchronous
completion. Instrumentation that owns the asynchronous operation, or the
application itself, can create a separate span for that work. This policy
applies to dynamic function spans; it does not define the lifecycle of
application-created spans or protocol spans.

The schema also describes optional attribute mappings and automatic capture;
these are not currently accepted by the Java or Node.js adapters. Each
`attributes` entry names a span attribute and has an `argument` object.
`argument.index` selects the zero-based source argument (0 through 11), and
optional `argument.type` describes that same argument using an OBI-defined
decoding hint: `u8`, `u16`, `u32`, `u64`, `i8`, `i16`, `i32`, `i64`, or
`string`. These hints are not language-specific types and do not configure the
output OpenTelemetry attribute type. The `automatic_attributes` boolean opts
into automatic argument/result capture; it defaults to `false`. When enabled,
explicit mappings take precedence over automatically captured attributes with
the same key; the automatic value is omitted. Spans may be declared only on
include rules; parsing rejects non-empty spans under exclude rules. Nested object
extraction is not supported by this configuration.

Malformed shared declaration structure is a configuration error. Runtime
implementations validate runtime-specific selector syntax and evaluate each
declaration independently: unresolved targets must not select arbitrary
candidates, and a failing target must not prevent valid siblings from applying.
Each runtime documents resolution diagnostics and attribute-collision behavior
in its runtime reference.

The schema describes a shared contract, not support in every runtime. Each
runtime documents its accepted function syntax, target types, and attributes in
its runtime-specific reference. Shared conversion validates declaration
structure and common support constraints; the selected runtime parses its
selector syntax and resolves targets at the runtime boundary.

The following Java runtime example uses the currently supported `on.function`
form. It omits attributes, which are not currently supported by the Java or
Node.js adapters.

```yaml
capture:
  rules:
    - name: checkout
      action: include
      match:
        process:
          exe_path_glob: "/opt/apps/*"
      refine:
        spans/development:
          - name: checkout.place_order
            on:
              function: "com.example.Checkout#placeOrder"
```
