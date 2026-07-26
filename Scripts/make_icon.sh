#!/usr/bin/env bash
# Regenerate Icon.icns from Design/icon.svg.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
exec swift Scripts/make_icon.swift
