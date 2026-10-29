# dot-trail

Equippable player trails: an image ribbon that follows a node. Read [docs/design.md](docs/design.md) first; it holds the reuse map, the data model, the equip rule and the store contract for the TMC backend.

**The distributable is `addons/dot_trail/`.** `project.godot` and `examples/` exist to validate it alone. It requires dot-core and, for the parts that extend official addons, dot-workbench, dot-game and dot-net (symlinks in `addons/`, gitignored). **The dependency runs one way: dot-trail extends dot-workbench and dot-game through their generic hooks; neither knows trails exist.** dot-cloud is reached by path.

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
| `workbench/dot_trail_workbench.gd` | `DotTrailWorkbench`: ops `trail_list/upload/delete`, flag `trail`, `/api/trails`, built on `DotWorkbenchHttp.mount_extension` and `DotWorkbenchApi.add_flag` |
| `net/dot_trail_message.gd`, `net/dot_trail_relay.gd` | `DotTrailMessage` (id only) and `DotTrailRelay`: the server checks a request through `DotTrailEquip` and tells everyone; a joiner hears who wears what; `revalidate` |
| `client/dot_trail_client.gd` | `DotTrailClient`: `attach(net, registry)`, `request(id)`, one emitter per wearer, `fetch_pack`; rule `sv_trail_pack=<id>@<version>` (`PACK_CVAR`), registered on the server console by `advertise(console, config)` as a notify cvar |
| `dot_trail_config.gd` | `DotTrailConfig`: cvars (`DOT_TRAIL_*`, `--trail-*`); `pack` (`--trail-pack`) is the `<id>@<version>` a server advertises, checked by `parse_pack` |

- Prices, purchases and entitlements belong to the TMC backend; this addon only receives the group and entitlement lists. Do not add HTTP calls here without updating the contract in the design note.
- Images are only ever read through `Image.load_*_from_buffer` after `DotTrailUpload.validate`; never load a pack's file as a resource.
- The addon ships no art; uploaders are responsible for the rights to what they upload.
- Validate: import, `--check-only` on every `.gd`, then `res://examples/trail_selftest.tscn` (8 sections, 98 checks), `workbench_selftest.tscn` (3 sections, 26 checks), `net_selftest.tscn` (24 checks) and `cloud_selftest.tscn` (4 sections, 17 checks: build, sign, advertise, then a started DotCloudClient fetches and mounts the pack through `DotGamePrejoin.extra_steps`, all from a local CDN directory), `tools/screenshot.sh out.png` renders a runner with trails (display needed), all through `heavy`. CI is the shared dot-ci `@v1`.

Wiring in a game (needs dot-game API level 31, which adds `extra_steps`): add `client.fetch_pack` to dot-game's `DotGamePrejoin.extra_steps` (`func(rules): return await trail_client.fetch_pack(cloud, rules)`; a failure is a warning and the join goes ahead), and `DotTrailWorkbench.new(api, store).mount(http)` for the owner/admin form. A server sets `pack` (`--trail-pack trails-x@1.0.0`) and calls `DotTrailClient.advertise(console, config)` once its console exists; publish the store directory with dot-cloud's `tools/publish_pack.sh --source <dir> --id trails-<server>` or `DotTrailPack.build`.
