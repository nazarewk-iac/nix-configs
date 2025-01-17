#!/usr/bin/env bash
set -eEuo pipefail

lspci -nn -k | grep -i -A"${2:-3}" "$1" "${@:3}"