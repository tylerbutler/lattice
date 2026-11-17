# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

### Fixed

- Count only reachable visible items in `sequence.length` after reordered delta
  delivery, so insertion at `length` succeeds. Keep nodes with missing parents
  until those parents arrive. ([#253](https://github.com/tylerbutler/lattice/issues/253))
