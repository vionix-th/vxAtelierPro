---
description: Text-to-speech system and persisted playlist model
globs: src/tts/**, src/system/export/TTSPlaylistExportData.swift
---
# TTS System

TTS layer has two parts:

- Playlist storage: persisted named playlists with ordered snapshot entries
- Playback controller: `TTSQueue` drives speech for active playlist

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

- Lives in `src/tts/control/TTSControlView.swift`
- Lists playlists
- Creates, renames, deletes playlists
- Imports and exports single playlists
- Shows current playlist entries
- Provides transport controls and repeat controls

### `TTSSettingsView`

- Manages role/language voice configuration
- Edits speech rate and pitch

## Import / Export

- Full backup includes playlists and entries
- Single playlist JSON export/import is supported through `DataManager` and `JsonSerializer`

## Notes

- Current playlist playback is snapshot-based
- Source message and conversation IDs are provenance only
- Playlist content does not require live conversation objects once created
