# Changelog

## Unreleased

- Requires just_game_engine ^2.0.0-dev.4.
- Terrain and spline colours go linear through the engine's `LinearColor.of` (was `GraphicsShapes.linear`).
- Installing the kit installs the engine's built-in components (`BuiltInComponents.extension`) too: its levels use them.
- **Breaking**: every component's name ends in `Component`: `Scatter3DComponent`, `Spline3DComponent`, `SplineSweep3DComponent`, `SplineInstances3DComponent`, `PathFollower3DComponent`, `Terrain3DComponent` (file `terrain_3d_component.dart`) and `GridTiles3DComponent`. Levels saved before are renamed as they load (`WorldBuilderKit.renamedTypes`).
- Mesh library format 2: a shape is saved under the engine's new name (`Cube3DComponent`); a version 1 library is read as before.
- **Breaking**: `ScatterSchemas`, `SplineSchemas`, `TerrainSchemas` and `TileSchemas` are `ScatterDefinitions`, `SplineDefinitions`, `TerrainDefinitions` and `TileDefinitions` (files `*_definitions.dart`; were `*_schemas.dart`), and `WorldBuilderKit.schemas` is `WorldBuilderKit.definitions`, a list of `ComponentDefinition`s, now that the engine has folded `ComponentSchema` into it.
- Requires just_game_engine_formats ^0.3.0: the kit depends on it directly, for the scene format's component renames (`V10ToV11.renames`) that the mesh library's older files follow.

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
