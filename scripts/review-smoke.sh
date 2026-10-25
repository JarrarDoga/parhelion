#!/usr/bin/env bash
# Throwaway file for testing the @claude reviewer. Do not merge.
# Deletes the build output for one target: review-smoke.sh <target>
target=$1
rm -rf $BUILD_ROOT/$target
