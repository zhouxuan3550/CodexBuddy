#!/bin/bash

artifact_zip_name() {
  local product_name="$1"
  local version="$2"
  local architecture="${3:-}"

  if [[ -n "$architecture" ]]; then
    printf '%s-v%s-%s.zip\n' "$product_name" "$version" "$architecture"
  else
    printf '%s-v%s.zip\n' "$product_name" "$version"
  fi
}

artifact_dmg_name() {
  local product_name="$1"
  local version="$2"
  local architecture="${3:-}"

  if [[ -n "$architecture" ]]; then
    printf '%s-v%s-%s.dmg\n' "$product_name" "$version" "$architecture"
  else
    printf '%s-v%s.dmg\n' "$product_name" "$version"
  fi
}
