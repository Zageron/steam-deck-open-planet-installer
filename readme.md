# Openplanet Installer

Install Openplanet for the Steam version of Trackmania on Steam Deck or Linux.

> [!WARNING]
> Read the disclaimer below before you use this script.

## Disclaimer

- GitHub Copilot used GPT-5.6 Luna to generate this script.
- ASD-STE100 for short and clear text.

## Purpose

The script finds the Steam installation and its game libraries.

The script uses Steam AppID `2225070` to find Trackmania.

The script downloads the current Openplanet archive.

The script checks the archive before it changes game files.

The script creates a copy before it installs new Openplanet files.

The script does not use Protontricks or change Steam launch options.

## Requirements

Install these tools:

- Bash
- `curl`
- 7-Zip with the `7z` or `7zz` command

Install Trackmania through Steam before you use this script.

## Install

CAUTION: Do not use Trackmania during the installation. Game operation can cause damage to game files.

1. Open a terminal.
2. Change to this project directory.
3. Start the script:

```bash
./install-open-planet.sh
```

The script finds Steam libraries from Steam's `libraryfolders.vdf` file.

The script installs Openplanet files in the Trackmania directory.

## Status

Examine the current installation:

```bash
./install-open-planet.sh --status
```

Install Openplanet again:

```bash
./install-open-planet.sh --force
```

The `--force` command creates a new copy before the installation.

## After Install

Launch Trackmania from Steam.

Push F3 to open Openplanet.

NOTE: The script does not add a `dinput8` launch option.

## Errors

If the script does not find Steam, start Steam. Then start the script again.

If the script does not find Trackmania, install it through Steam.

If 7-Zip is not found, install a package that provides `7z` or `7zz`.

If the archive is not correct, examine the network connection. Then start the script again.
