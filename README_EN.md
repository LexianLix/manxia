# Manxia · 漫匣

**Keep the stories you love within reach.**

A Flutter manga reader for Android built around the feel of a physical book.

[![Latest release](https://img.shields.io/github/v/release/LexianLix/manxia?style=flat-square&color=47745e)](https://github.com/LexianLix/manxia/releases)
[![Platform](https://img.shields.io/badge/Platform-Android-47745e?style=flat-square)](https://github.com/LexianLix/manxia/releases)
[![License](https://img.shields.io/badge/License-MIT-47745e?style=flat-square)](LICENSE)

[Download](#download--install) · [Changelog](CHANGELOG.md) · [Issues](https://github.com/LexianLix/manxia/issues)

> [中文](README.md) · [日本語](README_JA.md)

## About

Manxia is a manga reader for Android phones and tablets that brings discovery, a personal bookshelf, local import, and offline reading together in one app. Its interface is built on a cream-and-deep-green palette, with a three-dimensional bookshelf, covers that open along their spine, and a floating frosted-glass navigation bar — all designed to keep a little of the tactility of a real book.

Dongmanwu （动漫屋） is connected as the default source, with daily picks, full category browsing, filtered search, and the site's original rankings. You can also import your own images, CBZ files, or PDFs and organize them into a portable library. Collections, reading progress, and downloaded content stay on your device, with manual backup or WebDAV sync if you want them elsewhere.

## Features

- **3D bookshelf** — Covers are bound full-bleed like real books, with each spine tinted from its own cover art. Tapping a book swings the cover and pages open along the spine; going back closes the book into place. Momentum scrolling with spring snapping, adjustable density, and a list view are all supported.
- **Frosted-glass interface** — A floating frosted-glass bottom bar with droplet-style transitions and gesture-driven navigation that carries the current frame into the next screen. Reduced-motion and material-quality settings are available.
- **Plugin “reading rooms”** — A plugin store with install, enable/disable, update, configure, and uninstall. Themes, reading presets, manga sources, and navigation layouts can be combined freely; local plugin files and custom online repositories are supported.
- **Personalized home** — Five default sections (bookshelf, discover, downloads, plugins, settings), plus optional reading-history shortcuts, reorderable tabs, and a configurable start page. Per-book reading preferences include keep-screen-on, two-page defaults, background, and auto-hiding toolbars.
- **Manga discovery** — Daily picks, popularity / new-release / most-collected rankings, category, serialization-status, and sort filters with pagination, title and author search, search history, and follow-to-track for ongoing series.
- **Immersive reading** — Continuous vertical scroll, horizontal or vertical paging, left-to-right and right-to-left directions, and two-page spreads on wide screens. Plus a curved page-turn effect, pinch zoom, automatic margin cropping, auto-scroll, in-image position resume, and per-book settings.
- **Reading tools** — Chapter lists, multiple bookmarks, notes, page favorites, image preloading, and brightness, warmth, and background adjustments. Prepare the next chapter near the end, mark it read and continue, or return to the previous chapter at its saved position. Per-book one-hand presets, adjustable tap areas, and bottom-docked controls are available.
- **Library management** — Custom groups, tags, reading status, sorting, drag-and-drop, and batch operations. Reading history can be browsed and searched by date. Chapter read marks, book progress, pinned continue reading, and optional automatic archiving help organize your collection.
- **Offline & import** — A chapter download queue with concurrency control, pause/resume, retry, cache statistics, and CBZ export. Manage storage by book and chapter, set a download limit, filter read chapters, and preview batch cleanup while preserving library data. Import images, folders, ZIP/CBZ archives, and PDFs.
- **Backup & sync** — JSON data backups, and full library ZIP backups including offline images with a SHA-256 manifest. WebDAV supports metadata merging and full-library transfer.
- **Sources & preferences** — Configurable static-HTML manga sources with source health checks; if a catalog becomes unavailable, Manxia can search your other configured sources while keeping your collection and reading position intact. Larger text and Simplified Chinese, Traditional Chinese, and English UI are supported.

The bookshelf only shows your own collection — add titles from the Discover page on first launch. Rankings follow the source site's original order, and daily picks are drawn from the catalog without fabricated popularity numbers.

## Plugins & Creating Your Own

Manxia ships with built-in plugins such as Warm Paper Study, Blue Hour, Japanese Reading Habits, Long Webtoon Scroll, and Local Collection Room. You can also build your own: a plugin is defined by a JSON manifest covering themes, reading parameters, static-HTML manga sources, and navigation layouts — no recompilation of the app required.

See the plugin development guide for Plugin API 1, the manifest format, and complete templates; examples live in the `plugins/` directory. Developer tools provide manifest validation and catalog generation, online plugin installs are verified against SHA-256, and your personal library and per-book settings are always kept separate.

## Download & Install

Current release: **v0.4.2**, for **Android 7.0+**. Release APKs are signed with the project's fixed release key and split per architecture:

| Device | Package |
| --- | --- |
| Most Android phones & tablets (recommended) | ARM64 · arm64-v8a |
| Older 32-bit ARM devices | ARMv7 · armeabi-v7a |
| x86_64 devices or emulators | x86_64 |
| Integrity checksums | SHA256SUMS.txt |

Download the APK for your device from [GitHub Releases](https://github.com/LexianLix/manxia/releases) and install it. The in-app “Check for updates” option queries the latest GitHub release and offers a download link.

## Building from Source

Toolchain: **Flutter 3.47.7 / Dart 3.13.5**. Android builds also require **JDK 17 and the Android SDK**.

```bash
git clone https://github.com/LexianLix/manxia.git
cd manxia
flutter pub get
flutter build apk --release --split-per-abi
```

Before building for Android, complete the Android setup in `flutter doctor`. Self-built packages are signed with your own key and cannot update the official release builds in place — keep your keys and passwords out of the repository.

Checks:

```bash
flutter analyze --no-pub
flutter test --timeout 30s
```

## Contributing

Bug reports and suggestions are welcome via [Issues](https://github.com/LexianLix/manxia/issues), and pull requests improving the reading experience, source parsing, or accessibility are equally welcome. When reporting a bug, please include the app version, your device and OS version, reproduction steps, and screenshots or logs with personal information removed.

## License & Credits

Manxia's app code is released under the [MIT License](LICENSE) and was implemented independently; its visual design was inspired by Wenku8_Flutter. Bundled fonts are Adobe Source Han Serif (SIL OFL 1.1). See the repository's NOTICE file for full third-party declarations.

Rights to remote manga metadata, covers, and page content belong to their respective rights holders and are not covered by the app's license; the repository contains no manga page images.
