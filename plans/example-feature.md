# Example Feature

## Overview

This is an example PRD overview file. It lives at `plans/example-feature.md` and describes the feature as a whole. The corresponding task files live in `plans/example-feature/`.

When you run Ralph with `--label=example-feature`, it reads task files from `plans/example-feature/` and syncs work to the `feat/example-feature` branch.

## Goal

Add a widget that lets users configure their notification preferences, including email, push, and in-app channels.

## Scope

- User-facing settings page for notification preferences
- Backend API endpoint to persist preferences
- Email, push, and in-app notification dispatch

## Out of scope

- SMS notifications
- Admin-level notification overrides

## Tasks

See `plans/example-feature/` for the individual task files.
