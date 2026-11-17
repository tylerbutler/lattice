# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

### Fixed

- Keep `text.length` consistent with visible text after reordered delta delivery,
  so `append` succeeds before and after a missing parent arrives.
  ([#253](https://github.com/tylerbutler/lattice/issues/253))
