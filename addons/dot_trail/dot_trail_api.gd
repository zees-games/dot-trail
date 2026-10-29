extends RefCounted

## dot-trail's API level; the bump rule is on DotAddonApi in dot-core.

# 1: DotTrailDef, DotTrailRegistry, DotTrailEquip, DotTrailUpload, DotTrailRibbon, DotTrailEmitter, DotTrailConfig.
# 2: DotTrailWorkbench, DotTrailMessage, DotTrailRelay, DotTrailClient (moved here from dot-workbench and dot-game).
# 3: DotTrailEnvelope, DotTrailBackend (Stub, Http), the store UI (DotTrailScreen, DotTrailUploadPanel, DotTrailPreview, DotTrailFilePick, DotTrailKit, DotTrailMenu), relay receive/allows, client receive/apply_missing.
const LEVEL := 3
const OLDEST := 1
