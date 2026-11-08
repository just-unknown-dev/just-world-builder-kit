# Changelog

## 0.2.0-beta.1

### Breaking

- The files are laid out by feature: `lib/src/splines/`, `terrain/`, `tiles/`, `scatter/`, `kit/` and `editor/`, each with one barrel; the public libraries export only the barrels. Import `package:just_world_builder_kit/just_world_builder_kit.dart` and `/editor.dart`, never a `src/` file.
- Renamed (2-D/3-D tags beside the tagged components, and a definitions holder named after its component):
  - `SplineLinkSystem` → `Spline3DLinkSystem`, `GridTilesLinkSystem` → `GridTiles3DLinkSystem`, `TerrainLinkSystem` → `Terrain3DLinkSystem`;
  - `SplineDefinitions` → `Spline3DDefinitions`, `TileDefinitions` → `GridTiles3DDefinitions`, `TerrainDefinitions` → `Terrain3DDefinitions`, `ScatterDefinitions` → `Scatter3DDefinitions`;
  - `SweepRenderProvider.colourLimit` / `.colourCount` → `colorLimit` / `colorCount`;
  - `WorldBuilderKit.renamedTypes` → `WorldBuilderMigrations.renamedTypes` (with `WorldBuilderMigrations.install`);
  - `MeshLibraryFiles` → `WorldBuilderFiles`, which lists models too: `list()` (synchronous) → `Future<List<String>> libraries()`, plus `models()` and `refresh()`.
- Every component's name ends in `Component`: `Scatter3DComponent`, `Spline3DComponent`, `SplineSweep3DComponent`, `SplineInstances3DComponent`, `PathFollower3DComponent`, `Terrain3DComponent` (file `terrain_3d_component.dart`) and `GridTiles3DComponent`. Levels saved before are renamed as they load (`WorldBuilderMigrations.renamedTypes`), at any scene format.
- `ScatterSchemas`, `SplineSchemas`, `TerrainSchemas` and `TileSchemas` became `…Definitions` (now the `…3DDefinitions` above), and `WorldBuilderKit.schemas` is `WorldBuilderKit.definitions`, a list of `ComponentDefinition`s, now that the engine has folded `ComponentSchema` into it.
- Changed signatures: `MeshLibraryWorkspace(root:)` → `MeshLibraryWorkspace(files:)`; `scatterPanel(tool, root)` → `scatterPanel(tool, files)`; `makeTerrain` takes `root:`; `ScatterStrokeCommand` keeps what a stroke changed, not its `before` / `after` lists (`removedCount`, `addedCount`).
- Requires just_game_engine ^2.0.0, just_editor_core ^0.1.0 (the panels use `ReadonlyFieldRow`, was `ReadonlyRow`) and just_graphics_engine ^0.1.0 for its tests (the render providers fill `Render3DScene`s with `Shape3DMesh`es and `Material3DData`; were `RenderScene`, `ShapeMesh` and `MaterialData`). The store manifest asks for just_game_engine `^2.0.0` and just_game_engine_editor `^0.1.0`.

### Added

- `WorldBuilderMigrations` (`renamedTypes`, `install`), `TerrainFileCommand`, `TerrainSaveException`, `freeTerrainPath`, `MeshLibraries.changes`, `GridTileTool.maxFillCells`, `MeshLibraryWorkspaceState.loaded`.
- `test/library_layout_test.dart` (layout, layers, release split) and `test/store_manifest_test.dart`; the tests mirror `lib/src/`.
- Widget tests for three of the fixes below: a Scatter slider dragged as its panel closes is one undo step; the Scatter options bar shows a layer added after it was built, in its label and its menu; the Tiles panel shows a library's pieces when it is read, read again (`forget`) and let go (`releaseUnused`).

### Changed

- The link systems let go of the terrain files and mesh libraries no piece uses any more, whenever what the world's pieces use changes: a game that loads levels without `WorldBuilderKit.ready` no longer keeps every file it ever loaded.
- A Scatter stroke's undo step keeps what it changed, not two copies of every piece; a stroke tries only the grounds under its brush, found once a stroke; the brush's surface is looked for once an event.
- The Tiles tool's cells under the pointer are found by walking the ray through the grid, not by a look at every cell.
- The project's mesh libraries and models are listed once, off the UI thread, and again when one changes; the Tiles panel reads a library once (`ready`) and shows its pieces when it is read, or read again after a save.
- Blockout uses the editor's own plane and line maths (`HandleDrag`); the tools share their space, adoption, box-edge, brush-ring, clicked-points and option-picker parts.
- The tool picks a terrain, tile or sweep's normal through the inverse transpose of its entity's transform.
- The mesh library's older files follow the scene format's component renames through the engine's `SceneFormat.renamedComponents` (just_game_engine_formats 0.3.0); the kit no longer depends on just_game_engine_formats directly.
- The Level Designer tools take just_dart 0.3.0's `Ray3D` (was `Ray3`), through the engine. Terrain and spline colours go linear through the engine's `LinearColor.of` (was `GraphicsShapes.linear`).
- Installing the kit installs the engine's built-in components (`BuiltInComponents.extension`) too: its levels use them.
- Mesh library format 2: a shape is saved under the engine's new name (`Cube3DComponent`); a version 1 library is read as before.
- The code is formatted (`dart format`).

### Fixed

- Another terrain no longer takes over a terrain's file: its file is never one another terrain uses (renamed, or taken out) or one on disk, and the step that makes it puts and, undone, forgets its ground. Before, it could flatten another terrain's ground outside undo and save the flat ground over its file.
- The mesh library workspace no longer offers to save a file it could not read: nothing can be changed or saved before the file is read, and Save writes nothing then.
- Terrain sculpting shapes as much a metre whatever the pointer's event rate (a dab every quarter brush travelled), and a stroke that leaves the ground goes on from where it comes back.
- Tiles: an erase never makes an empty Grid Tiles 3D; a fill keeps its own box (Page Up/Down mid-fill no longer shrinks it to a cell) and spans 256 cells at most; a fast drag paints every cell it passes over; cells past what a grid's keys hold are not offered.
- Saving: a terrain file that cannot be written leaves the others written and fails the save (`TerrainSaveException`); a file changed while it was written stays unsaved.
- The Tiles panel no longer reads a library again on every pick, and shows a library's pieces once it is read and as they are after a save.
- Floor: a double-click with too few corners no longer adds the last corner twice. Scatter: a stroke where nothing lands makes no scatter; the options bar's layers are read as it is drawn; a slider drag the panel closes in the middle of is still one undo step. Brushes and the tile preview go when the pointer leaves the viewport. Picked normals stay square to the surface under a scale that differs by axis. A mesh library piece's name is kept when its field is left, not only on Enter. A path follower goes back to its start when its `startAt` or its path is edited while time stands still.
- The `WorldBuilderKit` dartdoc sample compiles: `EngineConfig(services: [Graphics3D(), Physics3D()])`.

### Removed

- `adoptEntities` is internal now (was public in `spline_tools.dart`).
- The flat `test/*.dart` files, split into `test/<feature>/`.

## 0.1.0-beta.1

First version: world building for just_game_engine in 3D.

- `WorldBuilderKit.extension`: the kit's components, field types and render providers; `WorldBuilderKit.systems()` / `registerSystems(world)`: what ties sweeps, tiles and terrains to their splines and files before physics, and moves path followers; `WorldBuilderKit.ready(world)`: reads a level's terrain files and tile libraries before it runs (solid from the first step) and lets go of those the last level used.
- `package:just_world_builder_kit/editor.dart` (design-time): `WorldBuilderModule`, a Level Designer kit for 3-D scenes ("World Builder" in its switch).
- Blockout: draw a box on any surface and pull it up to its height, outline a floor, drag a ramp or a flight of stairs from its foot to its top. Each makes the engine's own 3-D shapes, solid as they are (a static body and a collider matching the shape), one undo step.
- Splines: `Spline3D` (Catmull-Rom, Bezier or straight; open or closed; roll; a point given twice is one), `SplinePath` (length, rotation-minimising frames that meet where a closed spline closes, nearest point), `SplineSweep3D` (road, wall, pipe, rail; solid as its mesh), `SplineInstances3D` (copies in one batch), `PathFollower3D` (loop, back and forth or once, resting at the ends). Editor: the Spline tool, point handles, a splines overlay, laying the selection along a spline, baking copies into entities.
- Grid tiles: mesh libraries (`.meshlib.json`; a piece's number is never given to another) and their workspace, `GridTiles3D` (24 turns; cells packed with zlib), batches per piece and block of cells, collision merged along rows for whole-cell pieces and each piece's own shape otherwise (a new library's floors and walls are solid as their slabs). A piece whose shape cannot be made is solid as its cell and reported, never thrown. Editor: the Tiles tool (paint, erase, fill, pick; floors; turns; a drag stays on its level; selected tiles painted from their own library) and the Tiles panel.
- Terrain: `Terrain3D` and `.jterrain` files (heights, four layers' weights, holes), chunks rebuilt only where they changed, a height field with holes for collision — drawn holes match the solid ones triangle for triangle. Editor: the Terrain tool (raise, lower, smooth, flatten, noise, paint, holes), the Terrain panel; files written as the scene is saved; a shared file made unique into a name no file has.
- Scatter: `Scatter3D` layers (each a model, or one of the engine's shapes in its colour) and pieces (packed with zlib), batches per layer and square with a reach, opt-in box (turned and leant with its piece) or capsule collision. Editor: the Scatter brush and panel, and inspector editors for the layers and pieces; taking a layer out takes its pieces.
- Each piece's solid key is its own: a physics engine that keeps shapes by key never gives one scatter, grid or terrain another's collision.
- The editor picks the kit's pieces exactly: tiles by cell, swept roads by triangle, terrain by its ground.
- The brush and preview overlays (blockout, grid tiles, terrain, scatter) are what a tool in use draws, not gizmos (`gizmoKind` null): they stay with the editor's gizmos hidden.
- Packed cells, pieces and terrain bodies never unpack past their size limits: a damaged file fails with a `FormatException`.
- `just_store.json`: a kit; its editor part editor-only.
