# Contributing to Just World Builder Kit

Thank you for your interest in contributing to **Just World Builder Kit**. Bug fixes, features, tests and documentation are all welcome.

---

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Reporting Bugs and Suggesting Features](#reporting-bugs-and-suggesting-features)
- [Development Setup](#development-setup)
- [Working Against Unpublished Dependencies](#working-against-unpublished-dependencies)
- [How the Package Fits Together](#how-the-package-fits-together)
- [Running the Tests](#running-the-tests)
- [Coding Guidelines](#coding-guidelines)
- [Submitting a Pull Request](#submitting-a-pull-request)
- [Commit Message Convention](#commit-message-convention)
- [License](#license)

---

## Code of Conduct

This project follows our [Code of Conduct](CODE_OF_CONDUCT.md). By taking part you agree to its terms. Please report unacceptable behaviour to the maintainers.

---

## Reporting Bugs and Suggesting Features

Before opening an issue, search the [existing issues](https://github.com/just-unknown-dev/just-world-builder-kit/issues) and check that the problem happens on the latest version.

A bug report should have:

- a clear title;
- steps to reproduce, and what you expected instead of what happened;
- the output of `flutter --version`, and the platform (Android, iOS, Linux, macOS, Windows, web);
- the scene's `.scene.json`, or the smallest part of it that shows the problem: the entity with its `Spline3D`, `SplineSweep3D`, `GridTiles3D`, `Terrain3D` or `Scatter3D`, and its `RigidBody3D` and `Collider3D`;
- the files the piece reads: the `.meshlib.json` for tiles, the `.jterrain` for a terrain (zipped: it is binary);
- for something that draws wrongly, a screenshot, and whether the piece is solid where it is drawn;
- for an editor bug, the tool (Block, Floor, Ramp, Spline, Tiles, Terrain, Scatter), what you did with it, and whether an undo put it back.

Bugs often belong somewhere else:

- The kit says what is solid; the engine's 3-D physics makes it so. A collider bug you can show with the engine's own shapes (a `Cube3D` with a `Collider3D` set to match its shape) belongs in [just_game_engine](https://github.com/just-unknown-dev/just-game-engine/issues), and wrong physics with no kit component involved in [just_physics_engine](https://github.com/just-unknown-dev/just-physics-engine/issues), which runs Jolt.
- A model, light or material that draws wrongly with no kit component involved belongs in [just_graphics_engine](https://github.com/just-unknown-dev/just-graphics-engine/issues).
- A `.jterrain`, cells or pieces field that will not unpack, where the zlib stream itself is at fault, belongs in `just_deflate`.
- An editor bug you can show without `WorldBuilderModule` (the Level Designer itself, the inspector, undo) belongs in `just_game_engine_editor`.

For a feature, open an issue labelled **`enhancement`** that describes the problem it solves and how it should behave. The package's scope is building 3-D levels: blockout, splines and what is laid along them, grid tiles and their mesh libraries, terrain and scatter, and the Level Designer tools that make them. A change to how a component or a file (`.meshlib.json`, `.jterrain`) is saved affects every level a game has saved, so open the issue first and agree the approach before you write it.

---

## Development Setup

| Tool | Minimum version |
|------|-----------------|
| Dart | 3.12.2 |
| Flutter | 3.47.1 (`just_game_engine`'s 3-D graphics need it) |

There is no app to run here: you work on the package and its tests. To try a change in a real game, take a game made from the third-person template (`just_third_person_template`, whose `level_01` holds a demo of every piece) and override `just_world_builder_kit` in its `pubspec_overrides.yaml` with `path: ../just_world_builder_kit`. Its `lib/main_editor.dart` opens the editor, where **World Builder** is in the Level Designer's switch in a 3-D scene.

The kit is not published to pub.dev (`publish_to: none`). Games get it as an Asset Store item, described by `just_store.json`.

```bash
git clone https://github.com/just-unknown-dev/just-world-builder-kit.git just_world_builder_kit
cd just_world_builder_kit
flutter pub get
flutter test
```

The tests need no GPU and no native physics: they draw on the engine's null GPU device and check the solid shapes the kit hands the physics engine.

If you're working from the Just engine monorepo, run every command from `plugins/just_world_builder_kit`.

---

## Working Against Unpublished Dependencies

The package depends on four just_* packages: `just_game_engine`, `just_deflate`, `just_editor_core` and, for its tests, `just_game_engine_editor`. When a change needs an unreleased version of one of them, check it out next to this repository and point this package at it with a `pubspec_overrides.yaml` in the repository root:

```yaml
# pubspec_overrides.yaml: local only, never commit it.
dependency_overrides:
  just_game_engine:
    path: ../just_game_engine
  just_editor_core:
    path: ../just_editor_core
```

List only the ones you need. If an overridden package needs an unreleased version of a package it depends on in turn (`just_graphics_engine`, `just_physics_engine`, `just_dart`, `just_game_engine_formats`, …), add that one too. In the monorepo the file overrides every just_* package the kit reaches.

Then run `flutter pub get`. Delete the file (or the entry) and run `flutter pub get` again to go back to the published versions.

Do not change `pubspec.yaml` to a path dependency. If your pull request needs a version of a just_* package that is not published yet, say so in the pull request: this package can only be released after it.

The third-person template depends on this package. Its game adds `WorldBuilderKit.systems()` and awaits `WorldBuilderKit.ready` after loading a level (in `lib/game/third_person_game.dart`); the lists the Asset Store generates for it register `WorldBuilderKit.extension` and `WorldBuilderModule`; its `assets/tiles/blocks.meshlib.json` and `assets/terrain/` hold the demo's files. If you change the public API, a saved field, a file format or `just_store.json`, say in the pull request what the template will need.

---

## How the Package Fits Together

| Path | Contents |
|------|----------|
| `lib/just_world_builder_kit.dart` | The runtime library, safe in a release build on every platform, the web included |
| `lib/src/world_builder_kit.dart` | `WorldBuilderKit`: the extension, the systems and `ready` |
| `lib/src/splines/` | `Spline3D`, `SplineSweep3D`, `SplineInstances3D`, `PathFollower3D`; `SplinePath` (sampling, frames); `SplineSweeper` (the swept mesh); their schemas, render providers and systems |
| `lib/src/tiles/` | `GridTiles3D` and its packed cells; `GridOrientations` (the 24 turns); `MeshLibrary` (the `.meshlib.json` format) and `MeshLibraries` (what one engine has loaded); `GridTileSolids`; the render provider |
| `lib/src/terrain/` | `TerrainData` (the `.jterrain` format), `TerrainBrush`, `TerrainMesher`, `Terrain3D` and `TerrainFiles` (what one engine has loaded); the render provider and link system |
| `lib/src/scatter/` | `Scatter3D`, its layers and packed pieces; `ScatterSpacing`, `ScatterBrush`; the render provider |
| `lib/editor.dart`, `lib/src/editor/` | Design time only: `WorldBuilderModule`; the Block, Floor, Ramp, Spline, Tiles, Terrain and Scatter tools; spline handles and overlay; the Tiles, Terrain and Scatter panels; the mesh library workspace; the inspector editors; `WorldBuilderRayTest` (picking the kit's pieces) |
| `just_store.json` | The Asset Store manifest: the extension and module a game registers, the component types the kit adds, the setup code shown after installing it, and the editor-only libraries. The `just` CLI's release check reads that last list |
| `test/` | One file per piece (`splines_test.dart`, `spline_render_test.dart`, `tiles_test.dart`, `terrain_test.dart`, `scatter_test.dart`), `blockout_test.dart` (blockout, and the library boundary) and `panels_test.dart` (the side panel's sections) |

A few rules hold the package together. Keep them:

- **The runtime never reaches the editor.** Nothing that `lib/just_world_builder_kit.dart` reaches imports `dart:io`, `just_editor_core`, `just_game_engine_editor` or a file under `lib/src/editor/`. Files are read through the engine's seams (`EngineContext.bundle`, `EngineContext.tiles.readText`); the editor module points them at the project. `just_store.json` lists `editor.dart` and `src/editor/` as editor-only; keep it in step. `test/blockout_test.dart` checks the boundary.
- **3-D graphics and physics come through the engine.** The kit imports `package:just_game_engine/graphics_3d.dart` (render providers) and, in the editor, `package:just_game_engine/physics_3d.dart`, never `just_graphics_engine`, `just_physics_engine` or `just_jolt`. A piece is drawn by a `RenderProvider` and is solid as a `SolidShapeSource` that a `Collider3D` set to match its shape reads.
- **A solid key is its piece's own.** The engine keeps the shapes it builds by `solidKey`, across entities and levels. A key must change whenever the solid shape does and must never equal another piece's unless the shapes are the same: build it from the content, or from a token the instance owns and a revision it bumps. Never from a count every loaded instance shares, nor from `identityHashCode`.
- **Every saved component has a `ComponentSchema`** with 3-D hints (`Dimensions.threeD`, group "World Builder"), and its type is listed under `runtime.componentTypes` in `just_store.json`. The schemas are getters, so `WorldBuilderKit.extension`, a `RefreshableExtension`, can rebuild them after a hot reload. Write new ones as getters too.
- **Saved scenes and files must keep loading.** Never change a schema's `type` or `id`, a field's name, or the meaning of a byte in the packed cells, pieces or `.jterrain` files; a new field needs nothing more, because a scene saved without it loads the constructor's default. Bad data fails with a `FormatException` that says what is wrong, never a `TypeError` or a crash in a system's update.
- **Only settings are saved.** What the systems and providers keep (a sweep's mesh, a follower's progress, a grid's loaded library, revisions) is runtime state and never written to a saved field.
- **Metres, and up is -Y**, as everywhere in the engine. Heights in a `.jterrain` are measured up.
- **One undo step per stroke.** A tool's drag — a terrain stroke, a run of tiles, a scatter stroke, a handle dragged — is one entry in the editor's history, and undo puts it back exactly.

---

## Running the Tests

Run every command from the repository root. `test/blockout_test.dart` reads `lib/` from disk and expects that working directory.

```bash
# The whole suite.
flutter test

# One file.
flutter test test/terrain_test.dart
```

**The library boundary.** `test/blockout_test.dart` reads every runtime file under `lib/` and fails if one names `just_editor_core`, `just_game_engine_editor` or `src/editor/`, and checks that the editor part builds on `just_editor_core` alone.

**Writing tests.** There is no shared helper library. For a piece's data, build it by hand and check what it hands on: `solidParts`, a `ColliderShapes3D` built from it, `SplinePath` frames, `TerrainMesher.chunk`. For drawing, follow `test/spline_render_test.dart`: an `Engine` with `Graphics3D(device: NullGpuDevice(shaders: rendererNullShaders))` and `renderer.update(view)`. For a tool, follow the `editor` groups: an `EditorScope` with `WorldBuilderModule`, a `LevelDesignerSession` with an `OrbitFlyEditorView`, and presses, moves and releases at world points projected to the screen, then check `scope.history`. A tool that reads or writes files gets a temporary project folder (`WorldBuilderModule(root: ...)`).

---

## Coding Guidelines

- **Formatting.** Format the files you create with `dart format <files>`. Most files in the package are not formatted yet: do not reformat a file you only edit, or put a reformat of a whole file in a commit of its own, so that reviewers can see your change.
- **Analysis.** `flutter analyze` must report no issues at all: no errors, warnings or infos. The rules are in `analysis_options.yaml`: `flutter_lints`, with `build/` excluded.
- **Documentation.** Give every public API you add a `///` doc comment. Describe user-visible changes in [CHANGELOG.md](CHANGELOG.md), and update [README.md](README.md) if the public API changes.
- **Tests.** Add or update tests for any behaviour you change. A bug fix comes with a test that fails without it.
- **Dependencies.** Do not add a dependency without discussing it in an issue first.
- **Structure.** Runtime code goes in the files under `lib/src/` (outside `lib/src/editor/`) and reaches users through `lib/just_world_builder_kit.dart`; design-time code goes under `lib/src/editor/` and reaches users through `lib/editor.dart`.

---

## Submitting a Pull Request

1. Create a topic branch from `main`:
   ```bash
   git checkout -b fix/terrain-hole-edges
   ```
2. Make your change, following the [Coding Guidelines](#coding-guidelines).
3. Check that everything passes:
   ```bash
   dart format <the files you created>
   flutter analyze
   flutter test
   ```
4. Commit with a [conventional commit message](#commit-message-convention).
5. Push to your fork and open a pull request against `main`. Say what changed and why. List any unpublished just_* version it needs, and say whether it changes how a component or a file is saved or what the third-person template must do.
6. Answer review feedback.

Small pull requests are easier to review.

---

## Commit Message Convention

We use [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <short summary>
```

| Type | When to use |
|------|-------------|
| `feat` | New feature |
| `fix` | Bug fix |
| `docs` | Documentation only |
| `refactor` | Code change that neither fixes a bug nor adds a feature |
| `perf` | Performance improvement |
| `test` | Adding or updating tests |
| `chore` | Build process, tooling, dependencies |

Use the area as the scope: `splines`, `tiles`, `terrain`, `scatter`, `kit` or `editor`. Mark a change that breaks the public API or how scenes and files are saved with `!` and a `BREAKING CHANGE:` footer.

**Examples:**
```
fix(terrain): leave out only the triangles a hole touches
feat(editor): fill a box of tiles on any floor
docs(contributing): explain the solid key rule
```

---

## License

By contributing to Just World Builder Kit you agree that your contributions will be licensed under the [BSD-3-Clause License](LICENSE).
