# Contributing to Oracle enhanced adapter

Thanks for your interest in contributing! This document covers how to
report issues, open pull requests, and run the adapter's test suite
locally.

## Reporting issues

File issues at https://github.com/rsim/oracle-enhanced/issues. Please
include:

- Oracle enhanced adapter version (or commit SHA if you're on a branch)
- Oracle Database version
- Ruby engine and version (MRI / JRuby)
- A minimal reproduction — runnable code, expected vs. actual behavior

## Submitting pull requests

1. Fork the repository and create a topic branch off `master`.
2. Make your change. Include a regression test whenever practical.
3. Run the full spec suite (see below) and RuboCop.
4. Open a pull request against `rsim/oracle-enhanced:master` describing
   what changed and why.

## Development with devcontainer

The repository ships with a devcontainer configuration that provides a
complete development environment with Oracle Database and all required
dependencies pre-configured. It supports both x64 and ARM64 hosts, and
is the recommended way to work on the adapter.

### Prerequisites

- [Docker](https://www.docker.com/get-started) installed and running
- [VS Code](https://code.visualstudio.com/) with the
  [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)

### Getting started

1. Clone the repository:
   ```sh
   git clone https://github.com/rsim/oracle-enhanced.git
   cd oracle-enhanced
   ```
2. Open the project in VS Code:
   ```sh
   code .
   ```
3. When prompted, click "Reopen in Container" — or from the Command
   Palette (`Ctrl+Shift+P` / `Cmd+Shift+P`) run
   "Dev Containers: Reopen in Container".
4. VS Code builds and starts the environment automatically. This
   includes Ruby 4.0, Oracle Database Free (latest), Oracle Instant
   Client 23.26, and all gems from `bundle install`.

### What's included

- **Ruby**: 4.0
- **Oracle Database**: Free (latest)
- **Oracle Instant Client**: 23.26
- **Database configuration**:
  - Port `1521` is forwarded from the container
  - Service name: `FREEPDB1`
  - System password: `Oracle18`
  - TNS configuration in `ci/network/admin`
  - Test users are provisioned automatically via `ci/setup_accounts.sh`

## Running the test suite

Inside the devcontainer:

```sh
bundle exec rspec                                   # full suite
bundle exec rspec spec/path/to/file_spec.rb         # single file
bundle exec rspec spec/path/to/file_spec.rb:42      # single example
```

### Reproducing a specific run

Specs run in randomized order. The seed is printed at the start of the
run, e.g.:

```
==> Randomized with seed 12345 (reproduce: bundle exec rspec --seed 12345)
```

To reproduce that exact run:

```sh
bundle exec rspec --seed 12345
```

If a failure looks order-dependent, narrow it down to the minimal
failing pair with `--bisect`:

```sh
bundle exec rspec --seed 12345 --bisect
```

The seed line is also visible in CI job logs, including partial logs
when a run hangs and is cancelled.

## Running RuboCop

```sh
BUNDLE_ONLY=rubocop bundle install
BUNDLE_ONLY=rubocop bundle exec rubocop
```

These are the same commands CI runs (`.github/workflows/rubocop.yml`).
