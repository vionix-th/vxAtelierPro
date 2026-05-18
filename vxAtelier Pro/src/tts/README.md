---
description: Text-to-speech system and persisted playlist model
globs: src/tts/**, src/system/export/TTSPlaylistExportData.swift
---
# TTS System

TTS layer has two parts:

- Playlist storage: persisted named playlists with ordered snapshot entries
- Playback controller: `TTSQueue` drives speech for active playlist
- Export pipeline: `TTSPlaylistAudioExportService` coordinates writeout and `TTSPlaylistAudioExportRenderer` renders speech buffers

## Data Model

### `TTSPlaylist`

- Named playlist
- Persisted in SwiftData
- Owns ordered `TTSPlaylistEntry` records
- Tracks creation and update time for sorting

### `TTSPlaylistEntry`

- Stores playback snapshot
- Fields:
  - `role`
  - `text`
  - `sourceConversationID`
  - `sourceMessageID`
- Does not depend on live conversation state for playback

## Playback

### `TTSQueue`

- Selects active playlist
- Supports `play`, `pause`, `resume`, `stop`, `next`, `previous`
- Supports repeat modes:
  - `none`
  - `one`
  - `all`
- Uses language detection per utterance segment
- Resolves voice config by:
  - exact locale match
  - system default voice when no role/language configuration exists

## UI

### `TTSControlView`

- Lives in `src/tts/TTSControlView.swift`
- Split support types live in `src/tts/TTSControlSupport.swift` and `src/tts/TTSControlSubviews.swift`
- Lists playlists
- Creates, renames, deletes playlists
- Imports and exports single playlists
- Shows current playlist entries
- Provides transport controls and repeat controls

### `StatusBarTTSStrip`

- Lives in `src/views/statusbar/StatusBarRoots.swift`
- Shows playback state in the status bar
- Exposes play/pause and a sheet launcher
- Visibility is controlled by application settings

### `TTSSettingsView`

- Manages role/language voice configuration
- Edits speech rate and pitch

## Import / Export

- Full backup includes playlists and entries
- Single playlist JSON export/import is supported through `DataManager` and `JsonSerializer`
- Playlist audio export renders to `m4a` through Apple high-level APIs with a PCM intermediary

## Notes

- Current playlist playback is snapshot-based
- Source message and conversation IDs are provenance only
- Playlist content does not require live conversation objects once created
- No automatic sheet opening on playback start
