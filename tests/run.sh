#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp_dir="$repo_dir/tests/.tmp"
fixture="$repo_dir/tests/fixtures/project"
dep_src="$repo_dir/tests/fixtures/dep-src"

rm -rf "$tmp_dir"
mkdir -p "$tmp_dir/dep" "$fixture/bin"

if ! command -v javac >/dev/null 2>&1; then
  echo "SKIP: javac not found"
  exit 0
fi

javac -d "$tmp_dir/dep" $(find "$dep_src" -name '*.java')
jar cf "$tmp_dir/tiny-dep.jar" -C "$tmp_dir/dep" .

cat > "$fixture/.classpath" <<CLASSPATH
<?xml version="1.0" encoding="UTF-8"?>
<classpath>
  <classpathentry kind="src" path="src"/>
  <classpathentry kind="con" path="org.eclipse.jdt.launching.JRE_CONTAINER"/>
  <classpathentry kind="lib" path="$tmp_dir/tiny-dep.jar"/>
  <classpathentry kind="output" path="bin"/>
</classpath>
CLASSPATH

nvim --headless -u NONE -l "$repo_dir/tests/unit/run.lua"
nvim --headless -u NONE -l "$repo_dir/tests/integration/run.lua"
