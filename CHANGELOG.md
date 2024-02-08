# Changelog

All notable changes to this project will be documented in this file.
This project adheres to [Semantic Versioning](http://semver.org/).

## [Unreleased]

## [2.1.0] - 2024-02-08
### Changed
- Update GitHub Actions versions ([#117](https://github.com/ManageIQ/inventory_refresh/pull/117))
- Update actions/checkout version to v4 ([#118](https://github.com/ManageIQ/inventory_refresh/pull/118))
- Allow rails 7 gems in gemspec ([#119](https://github.com/ManageIQ/inventory_refresh/pull/119))

## [2.0.0] - 2022-09-06
### Added
- Add timeout-minutes to setup-ruby job (#110)
- Add ruby3 compliant parameters for lazy_find (#112)
- Handle two hash arguments to lazy_find (#114)

### Removed
- **BREAKING** Remove deprecated find_by/lazy_find_by methods

## [1.1.0] - 2022-05-03
### Changed
- Ruby 3 keyword arguments (#109)

### Added
- Cron for GitHub Actions (#108)

## [1.0.0] - 2022-02-09
### Changed
- Run rubocop -A (#102)
- Switch from travis to github actions (#104, #105)

### Added
- **BREAKING** Add back support for non-concurrent-safe batch strategies (#101)
- Add support for Rails 6.1 (#103)
- Add bundler-inject (#106)

### Fixed
- Fix InventoryCollection missing cache returns (#107)
