# Universe Install

[![Shell](https://img.shields.io/badge/shell-bash-4EAA25?logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Universe](https://img.shields.io/badge/universe-installer-6f42c1)](https://github.com/universeclouddev/universe)
[![GitHub repo](https://img.shields.io/badge/github-universeclouddev%2Finstall-181717?logo=github)](https://github.com/universeclouddev/install)
[![License](https://img.shields.io/badge/license-see%20Universe%20repository-blue)](https://github.com/universeclouddev/universe)

`universeclouddev/install` is the installer repository for [Universe](https://github.com/universeclouddev/universe). It provides a simple Bash installer that clones Universe, lets you choose where to install it, lets you select optional extensions, builds the selected modules from source, and prepares a runtime directory.

Universe is a single-JAR orchestrator for running and managing application instances across master and wrapper nodes. The installer is meant to make the first setup easier without hiding where files are placed.

## What the installer does

- Asks for an install directory.
- Clones `github.com/universeclouddev/universe` into `<install directory>/source`.
- Defaults to the upstream `production` branch, with an option to select and validate another branch or tag.
- Lets you choose optional Universe extensions.
- Lets you choose compile or pre-compiled mode.
- Builds from source with Gradle.
- Creates a runtime directory at `<install directory>/runtime`.
- Creates starter `config.json` and `database.json` files when they do not already exist.
- Copies loader, app, and API JARs into `<install directory>/runtime/jars`, and optional extension JARs into `<install directory>/runtime/extensions`.

Pre-compiled installs are shown in the installer, but they are not available yet. Choosing that option currently falls back to source compilation.

## Requirements

- Bash
- Git
- Java compatible with the Universe source target
- Internet access for Git and Gradle dependency downloads

Universe currently targets a modern Java toolchain. If the build fails because of Java, install the JDK version required by the upstream Universe repository and run the installer again.

## Quick start

```bash
git clone https://github.com/universeclouddev/install.git
cd install
./install.sh
```

After the install finishes, the script prints the command to start Universe from the runtime directory.

## Directory layout

If you keep the default install path, the result looks like this:

```text
~/universe/
├── source/       # Cloned Universe source repository
└── runtime/      # Runtime files used to start an instance
    ├── config.json
    ├── database.json
    ├── configuration/
    ├── data/
    ├── extensions/
    ├── jars/
    ├── running/
    └── templates/
```

## Extensions

The installer can build selected extension modules from the Universe source tree. Available choices include Docker, Kubernetes, S3 storage, database providers, metrics providers, GitOps, ArgoCD, Discord, and Tailscale. Extension JARs are copied to `runtime/extensions`, which is the directory Universe scans at startup; they are deliberately copied rather than symlinked so the runtime remains usable if the source checkout is moved, cleaned, or rebuilt.

Only select extensions that you plan to use. This keeps the build smaller and easier to understand.

## Running Universe

From the runtime directory, run the loader JAR printed by the installer:

```bash
cd ~/universe/runtime
java -jar jars/universe-loader-0.0.1.jar
```

The exact JAR name can change with the upstream Universe version. Check `runtime/jars` if the printed command differs.

## Configuration

The installer creates a basic master-node `config.json` if one does not already exist:

```json
{
  "address": "127.0.0.1",
  "port": 6000,
  "apiPort": 7000,
  "nodeId": "node-1",
  "clusterName": "universe-cluster",
  "isMasterNode": true,
  "masterAddress": "127.0.0.1",
  "masterPort": 6000,
  "masterApiPort": 7000
}
```

Edit this file before production use, especially when running multiple nodes.

## Updating

Run the installer again and choose the same install directory. If a prior installation (or a source checkout) is found, the installer asks whether to update the source with `git pull --ff-only`. Choosing **no** preserves the checked-out revision: the installer does not fetch, check out another branch, or pull, and builds that existing revision instead.

## Notes

- The installer does not overwrite existing `config.json` or `database.json` files.
- The installer keeps source and runtime files separate.
- The installer compiles from source until official pre-compiled downloads are available.
