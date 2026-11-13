# Balatro Portrait

Custom portrait-mode development repository for Balatro.

## Upstream

This project is based on [Balatro Portrait Mobile](https://github.com/LoreanXavier/balatro-portrait-mobile), which provides the portrait-mode build system and mobile patches. Original project code and notices are to be preserved with attribution and under their applicable licenses.

## Current baseline

- Target device: iPhone 11 (primary UI validation target)
- Uploaded iOS package: `Balatro-plus-v1-4-9.ipa`
- iOS bundle version: `1.0.17`
- Internal game version: `1.0.1o`
- Internal build target: `PROD_mobile`

The uploaded IPA is being checked against the upstream mobile patch set before it is used as a build source. Do not redistribute game binaries or proprietary game assets in this repository.

## Development rules

- Keep the GitHub repository on a single `main` branch.
- Do not create additional branches unless explicitly authorized.
- Preserve upstream attribution and license notices.
- Keep game-owned source and assets out of commits; builds should use a legally owned local copy of Balatro.
