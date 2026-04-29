# Changelog

## [0.2.0](https://github.com/xvzc/cbox.nvim/compare/v0.1.0...v0.2.0) (2026-04-29)


### ⚠ BREAKING CHANGES

* rename `style` option to `theme`

### Features

* auto-load entry point at plugin/cbox.lua ([de53037](https://github.com/xvzc/cbox.nvim/commit/de53037896fc2b971fc3530d7120b2c33a4473a9))
* auto-setup with vim.g.cbox_loaded guard ([e760753](https://github.com/xvzc/cbox.nvim/commit/e76075334e0302154563ad31bcaa5f14a1aa8a4e))
* **comment:** vline_style + spanning block detect, demote to line on unwrap ([60346f0](https://github.com/xvzc/cbox.nvim/commit/60346f0f996bdcadba8e8362e11f39a49d5e73d9))
* flatten comment_str and enable commentstring fallback ([a858f4d](https://github.com/xvzc/cbox.nvim/commit/a858f4d657bdbb8b10b600aff8dfe585c162aff6))
* **opts:** nest V-line-only opts under visual_line + dangling delimiter ([540009a](https://github.com/xvzc/cbox.nvim/commit/540009a694585b43ea0013b7173c9bc883c260a5))
* **render:** selection-aware wrap/unwrap and canonical comment prefix ([c380a15](https://github.com/xvzc/cbox.nvim/commit/c380a15a6d98d7f39de3fc21de7394401a3ee380))
* **wrap:** normalize leading/trailing whitespace symmetric with unwrap ([b51471c](https://github.com/xvzc/cbox.nvim/commit/b51471c8f7dde7e152319fe083280e73ee48dcfd))


### Bug Fixes

* **render:** blockwise wrap shrinks col range to tight non-whitespace span ([f012620](https://github.com/xvzc/cbox.nvim/commit/f012620874bf2c9502bc507c3d719657510cad27))
* **render:** V-line wrap and unwrap respect actual box position ([1e50ebe](https://github.com/xvzc/cbox.nvim/commit/1e50ebee8227622a36ebe673e116536285f41679))


### Code Refactoring

* rename `style` option to `theme` ([e4a5e32](https://github.com/xvzc/cbox.nvim/commit/e4a5e324d37f67d0e3642ed0b8c4313651f1be99))
