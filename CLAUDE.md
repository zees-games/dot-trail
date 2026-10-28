# dot-trail

Equippable player trails: an image ribbon that follows a node. Read [docs/design.md](docs/design.md) first; it holds the reuse map, the data model, the equip rule and the store contract for the TMC backend.

**The distributable is `addons/dot_trail/`.** `project.godot` and `examples/` exist to validate it alone. It requires dot-core (`ln -s ../../dot-core/addons/dot_core addons/dot_core`, gitignored); everything else is duck-typed.

| Path | What |
| --- | --- |
| `dot_trail_def.gd` | `DotTrailDef`: one trail, `from_dict` checks every field |
| `dot_trail_upload.gd` | `DotTrailUpload.validate`: png/webp by magic bytes, size, dimensions, nothing after the image; pure |
| `dot_trail_registry.gd` | `DotTrailRegistry`: the set, `trails.json` index, pack file list, the access rule `may_equip`; installed through `DotRegistry` |
| `dot_trail_equip.gd` | `DotTrailEquip`: server-side who wears what, cooldown, `revalidate` |
| `dot_trail_ribbon.gd` | `DotTrailRibbon.strip`: ribbon geometry as a pure function |
| `dot_trail_emitter.gd` | `DotTrailEmitter`: follows a node via `DotNodeRef`, keeps points headless, draws only with a display |
| `dot_trail_store.gd` | `DotTrailStore`: the upload form's core (`submit` needs licence from the CDN list, author, url), the store directory = the pack source (trails.json, images, licence.json) |
| `dot_trail_pack.gd` | `DotTrailPack`: `build` publishes the store as ONE dot-cloud pack (publisher by path), `fetch` ensures it through a DotCloudClient and loads it |
| `dot_trail_config.gd` | `DotTrailConfig`: cvars (`DOT_TRAIL_*`, `--trail-*`) |

- Prices, purchases and entitlements belong to the TMC backend; this addon only receives the group and entitlement lists. Do not add HTTP calls here without updating the contract in the design note.
- Images are only ever read through `Image.load_*_from_buffer` after `DotTrailUpload.validate`; never load a pack's file as a resource.
- The addon ships no art; uploaders are responsible for the rights to what they upload.
- Validate: import, `--check-only` on every `.gd`, then `res://examples/trail_selftest.tscn` (8 sections, 94 checks), `tools/screenshot.sh out.png` renders a runner with trails (display needed), all through `heavy`. CI is the shared dot-ci `@v1`.

The other halves live elsewhere: the owner/admin form in dot-workbench (`DotWorkbenchTrails`, flag `trail`, `/api/trails`), replication and the pre-join fetch in dot-game (`DotGameTrailMessage`, `DotGameTrailRelay`, `DotGameTrailClient`, rule `sv_trail_pack=<id>@<version>`). A server advertises the pack through that rule; publish the store directory with dot-cloud's `tools/publish_pack.sh --source <dir> --id trails-<server>` or `DotTrailPack.build`.
