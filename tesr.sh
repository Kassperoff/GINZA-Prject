#!/usr/bin/env bash

CORE="${0%/*}/rr.sh"
[  -f "$CORE" ] && source "$CORE"

pfsd2 &
