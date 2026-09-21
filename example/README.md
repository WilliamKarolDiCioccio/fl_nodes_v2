# fl_nodes_v2 example

A workflow editor demonstrating every feature of the package, and the only
thing that exercises the editor end to end — the pre-commit hooks run this
suite on any change to `lib/`, not just on changes here.

```sh
fvm flutter run -d linux
```

It is also [live on GitHub Pages](https://williamkaroldicioccio.github.io/fl_nodes_v2/),
built for the web from `master` by `../.github/workflows/demo.yml`.

What it covers:

- Seven node types, all registered prototypes, all creatable from the canvas
  menu.
- A **Form** node whose body is real Flutter input — text field, checkbox,
  slider, colour menu — keeping focus and state through drags and reselection.
- Derived ports: **Format** grows an input per `{n}` in its template,
  **Fan out** grows an exit each time the last free one is wired.
- Link captions, one editable by the app user and one derived from the port it
  leaves.
- An inspector panel that stays in sync purely by listening to the controller.
- Save and load as JSON through `controller.project`, wired here to the system
  clipboard so there is no file picker to install.
- Running the graph, with the trace and the produced value reported.
- Stress graphs up to 5000 nodes, with a status chip reporting how many nodes
  were actually built and how many times the path cache rebuilt.

## Benchmarks

```sh
fvm flutter test benchmark/demo_benchmark.dart          # node bodies built per frame
fvm flutter run --profile -d linux -t lib/bench.dart    # real FrameTiming
fvm flutter run --profile -d linux -t lib/bench.dart --dart-define=MODE=bare
```

`MODE=bare` renders a single `Text` instead of the editor. **Run it first on
any raster complaint** — see `../CLAUDE.md` for the two-GPU trap it exists to
rule out.
