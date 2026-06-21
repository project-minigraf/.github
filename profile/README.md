# Minigraf

**The SQLite of bi-temporal graph databases** — embedded, single-file, zero configuration.

A tiny Rust library that gives any application a persistent, queryable graph store with full time-travel history. No server. No setup. One `.graph` file.

**[Try it in your browser →](https://minigraf-playground.vercel.app/)**

---

## What it does

```datalog
; Store facts with valid-time ranges
(transact [[:alice :works-at :acme  {:valid-from "2022-01-01"}]
           [:alice :works-at :globo {:valid-from "2024-06-01"}]])

; Ask what was true at any point in the past
(query [:find ?company
        :valid-at "2023-06-01"
        :where [?e :name "Alice"]
               [?e :works-at ?company]])
```

Minigraf tracks **two independent time axes** — when something was true in the world, and when you recorded it — so you can always answer *"what did we know, and when did we know it?"*

---

## Ecosystem

| Repo | Description |
|------|-------------|
| [minigraf](https://github.com/project-minigraf/minigraf) | Core library (Rust) |
| [minigraf-python](https://github.com/project-minigraf/minigraf-python) | Python bindings |
| [minigraf-node](https://github.com/project-minigraf/minigraf-node) | Node.js bindings |
| [minigraf-wasm](https://github.com/project-minigraf/minigraf-wasm) | Browser / WASI bindings |
| [minigraf-java](https://github.com/project-minigraf/minigraf-java) | JVM bindings |
| [minigraf-android](https://github.com/project-minigraf/minigraf-android) | Android bindings |
| [minigraf-swift](https://github.com/project-minigraf/minigraf-swift) | Swift / iOS bindings |
| [minigraf-c](https://github.com/project-minigraf/minigraf-c) | C bindings |
| [minigraf-playground](https://github.com/project-minigraf/minigraf-playground) | Browser playground |
| [minigraf-inspector](https://github.com/project-minigraf/minigraf-inspector) | `.graph` file inspector |
| [minigraf-visualizer](https://github.com/project-minigraf/minigraf-visualizer) | Time-travel visualizer |
| [minigraf-examples](https://github.com/project-minigraf/minigraf-examples) | Examples and cookbooks |
| [temporal_reasoning](https://github.com/project-minigraf/temporal_reasoning) | MCP server for AI agents |

---

## Links

- [Documentation](https://docs.rs/minigraf) · [crates.io](https://crates.io/crates/minigraf) · [Playground](https://minigraf-playground.vercel.app/) · [Changelog](https://github.com/project-minigraf/minigraf/blob/main/CHANGELOG.md)
