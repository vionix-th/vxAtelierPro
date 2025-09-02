# vxAtelier Pro

**vxAtelier Pro** is a modern, extensible AI-powered writing and conversation assistant for macOS and iOS. It enables users to manage projects, organize conversations, interact with multiple AI providers, and customize their experience with advanced settings, prompt templates, and text-to-speech features.

---

## Table of Contents
- [Overview](#overview)
- [Features](#features)
- [Architecture](#architecture)
- [Data Models](#data-models)
- [AI Provider Support](#ai-provider-support)
- [Configuration & Customization](#configuration--customization)
- [Usage](#usage)
- [Building & Running](#building--running)
- [Logging](#logging)
- [Contributing](#contributing)
- [License](#license)

---

## Overview

vxAtelier Pro is designed for writers, researchers, and professionals who want to harness the power of state-of-the-art AI models in a structured, project-oriented environment. It supports multiple AI providers, rich conversation management, and deep customization, all built with the latest Swift, SwiftUI, and SwiftData best practices.

- **Platforms:** macOS (14+), iOS (17+)
- **Tech Stack:** Swift 5.9+, SwiftUI, SwiftData, [swift-markdown](https://github.com/apple/swift-markdown)

---

## Features
- **AI Conversations:** Start, manage, and organize conversations with leading AI models.
- **Project Management:** Group dialogs into projects for better organization.
- **Multi-Provider AI Support:** Seamlessly switch between OpenAI, Anthropic, xAI, and DeepSeek.
- **Prompt Templates:** Create and reuse system/user prompt templates for consistent results.
- **Text-to-Speech (TTS):** Customizable voice feedback with per-role and per-language configuration.
- **Web Search Integration:** Configure and use web search providers (e.g., Google Custom Search) in conversations.
- **Bookmarks:** Save and quickly access important messages within dialogs.
- **Export/Import & Backup:** Export projects, dialogs, or selected messages; backup and restore all data.
- **Rich Settings:** Fine-tune appearance, markdown, TTS, API keys, and more.
- **Logging & Status Bar:** Integrated logging with a status bar and log history sheet.

---

## Architecture

The codebase is modular, leveraging modern Swift, SwiftUI, and SwiftData best practices. It is organized into distinct modules for AI services, data models, system-level components, UI views, and utilities.

For a comprehensive overview of the architecture, module responsibilities, and key design patterns, please see the detailed documentation in `DEVELOPER.md`.

---

## Building & Running

- **Requirements:**
  - Swift 5.9+
  - Xcode 15+
  - macOS 14+ or iOS 17+
- **Dependencies:**
  - [swift-markdown](https://github.com/apple/swift-markdown)

**Build:**
```sh
xcodebuild -scheme "vxAtelier Pro"
```

**Lint/Test Compile:**
```sh
swift build
```

---

## Contributing

Contributions are welcome! Please follow Swift, SwiftUI, and SwiftData best practices. Refer to `TROUBLESHOOTING.md` for common pitfalls. All new features should include documentation and tests where appropriate.

---
