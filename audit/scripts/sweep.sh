#!/usr/bin/env bash
# usage: sweep.sh <repo> <out-dir>
set -uo pipefail

repo=$(cd "$1" && pwd)
mkdir -p "$2"
out=$(cd "$2" && pwd)
here=$(cd "$(dirname "$0")" && pwd)
deps=${AUDIT_DEPS:-${TMPDIR:-/tmp}/audit-skill-deps}
summary=$out/summary.txt
: >"$summary"
cd "$repo" || exit 1
files=$(git ls-files -co --exclude-standard)

has() { command -v "$1" >/dev/null 2>&1; }
note() { echo "$*" | tee -a "$summary"; }
skip() { note "$(printf '%-9s %-34s %s' skipped "$1" "$2")"; }

run() {
  local label=$1 dir=$2
  shift 2
  local log=$out/${label//[^A-Za-z0-9._-]/_}.txt
  (cd "$repo/$dir" && "$@") </dev/null >"$log" 2>&1
  local code=$? status=ok
  [ "$code" -ne 0 ] && status="exit $code"
  note "$(printf '%-9s %-34s %5s lines  %s' "$status" "$label" "$(wc -l <"$log" | tr -d ' ')" "$log")"
}

manifest_dirs() {
  grep -E "(^|/)($1)\$" <<<"$files" | sed -E 's#(^|/)[^/]+$##; s#^$#.#' | sort -u
}

files_in() {
  if [ "$1" = . ]; then
    grep -E "$2" <<<"$files"
  else
    grep -E "$2" <<<"$files" | grep "^$1/" | sed "s#^$1/##"
  fi
}

go_sweep() {
  local d=$1 p="go:$1" f pkgs=() gofiles=()
  has go || {
    skip "$p" "go not installed"
    return
  }
  while IFS= read -r f; do pkgs+=("$f"); done < <(
    cd "$d" && go list -f '{{.Dir}}' ./... 2>/dev/null | grep -v /node_modules/ | sed "s#^$(pwd -P)#.#"
  )
  [ ${#pkgs[@]} -gt 0 ] || {
    skip "$p" "go list found no packages"
    return
  }
  while IFS= read -r f; do gofiles+=("$f"); done < <(files_in "$d" '\.go$')
  run "$p gofmt" "$d" gofmt -l "${gofiles[@]}"
  run "$p vet" "$d" go vet "${pkgs[@]}"
  if ! has golangci-lint; then
    run "$p staticcheck" "$d" go run honnef.co/go/tools/cmd/staticcheck@latest "${pkgs[@]}"
  elif compgen -G "$d/.golangci.*" >/dev/null; then
    run "$p golangci-lint" "$d" golangci-lint run "${pkgs[@]}"
  else
    run "$p golangci-lint" "$d" golangci-lint run --default=standard \
      --enable=unparam,unconvert,wastedassign,nilerr,bodyclose,sqlclosecheck,rowserrcheck,errorlint,gocritic,usestdlibvars,copyloopvar,intrange,misspell,durationcheck,makezero "${pkgs[@]}"
  fi
  run "$p deadcode" "$d" go run golang.org/x/tools/cmd/deadcode@latest -test "${pkgs[@]}"
  run "$p govulncheck" "$d" go run golang.org/x/vuln/cmd/govulncheck@latest "${pkgs[@]}"
}

js_sweep() {
  local d=$1 p="js:$1" pm=npm lock f
  has node || {
    skip "$p" "node not installed"
    return
  }
  local pkg=$repo/$d/package.json bin=$repo/$d/node_modules/.bin
  has_script() { node -e 'process.exit(require(process.argv[1]).scripts?.[process.argv[2]] ? 0 : 1)' "$pkg" "$1"; }
  has_dep() { node -e 'const p = require(process.argv[1]); process.exit({ ...p.dependencies, ...p.devDependencies }[process.argv[2]] ? 0 : 1)' "$pkg" "$1"; }
  [ -d "$repo/$d/node_modules" ] || note "warning   $p has no node_modules, install dependencies for full results"
  for lock in pnpm-lock.yaml:pnpm bun.lock:bun bun.lockb:bun yarn.lock:yarn; do
    if [ -f "$repo/$d/${lock%%:*}" ] || [ -f "$repo/${lock%%:*}" ]; then
      pm=${lock##*:}
      break
    fi
  done

  if has_script lint; then
    run "$p lint" "$d" "$pm" run lint
  elif [ -x "$bin/eslint" ]; then
    run "$p eslint" "$d" "$bin/eslint" .
  elif [ -x "$bin/biome" ]; then
    run "$p biome" "$d" "$bin/biome" check .
  fi
  [ -x "$bin/prettier" ] && run "$p prettier" "$d" "$bin/prettier" --check .

  if has_script typecheck; then
    run "$p typecheck" "$d" "$pm" run typecheck
  elif has_script type-check; then
    run "$p typecheck" "$d" "$pm" run type-check
  elif [ -f "$repo/$d/tsconfig.json" ] && [ -x "$bin/tsc" ]; then
    run "$p tsc" "$d" "$bin/tsc" -b --noEmit
  fi

  run "$p knip" "$d" npx -y knip --no-progress
  has_dep react && run "$p react-doctor" "$d" npx -y react-doctor@latest . --verbose

  case $pm in
  npm) run "$p npm-audit" "$d" npm audit ;;
  pnpm) run "$p pnpm-audit" "$d" pnpm audit ;;
  bun) run "$p bun-audit" "$d" bun audit ;;
  *) skip "$p audit" "no audit command for $pm" ;;
  esac

  local css=()
  while IFS= read -r f; do css+=("$f"); done < <(files_in "$d" '\.css$' | grep -v node_modules/)
  [ ${#css[@]} -gt 0 ] || return 0
  if compgen -G "$repo/$d/.stylelintrc*" >/dev/null || compgen -G "$repo/$d/stylelint.config.*" >/dev/null; then
    [ -x "$bin/stylelint" ] && run "$p stylelint" "$d" "$bin/stylelint" -f compact "${css[@]}"
  else
    [ -d "$deps/node_modules/stylelint-config-recommended" ] ||
      npm install --prefix "$deps" stylelint@17 stylelint-config-recommended@18 >/dev/null 2>&1
    local cfg=$out/stylelint.json
    local tw='{"ignoreAtRules":["theme","utility","apply","custom-variant","variant","source","plugin","config","reference","tailwind","layer"]}'
    echo "{\"extends\":[\"stylelint-config-recommended\"],\"rules\":{\"at-rule-no-unknown\":[true,$tw],\"at-rule-prelude-no-invalid\":[true,$tw],\"at-rule-no-deprecated\":null}}" >"$cfg"
    run "$p stylelint" "$d" "$deps/node_modules/.bin/stylelint" --config "$cfg" --config-basedir "$deps" -f compact "${css[@]}"
  fi
  local entry
  entry=$(cd "$repo/$d" && grep -lE "@import ['\"]tailwindcss['\"]" "${css[@]}" | head -1)
  [ -n "$entry" ] && run "$p tailwind" "$d" node "$here/tailwind-lint.mjs" "$entry"
}

py_sweep() {
  local d=$1 p="py:$1" ruff=(ruff)
  if ! has ruff; then
    has uvx || {
      skip "$p" "ruff and uv not installed"
      return
    }
    ruff=(uvx ruff)
  fi
  run "$p ruff" "$d" "${ruff[@]}" check .
  run "$p ruff-format" "$d" "${ruff[@]}" format --check .
  if has mypy && { [ -f "$d/mypy.ini" ] || grep -qs '^\[tool\.mypy\]' "$d/pyproject.toml"; }; then
    run "$p mypy" "$d" mypy .
  fi
  if has pyright && { [ -f "$d/pyrightconfig.json" ] || grep -qs '^\[tool\.pyright\]' "$d/pyproject.toml"; }; then
    run "$p pyright" "$d" pyright
  fi
  has uvx || return 0
  run "$p vulture" "$d" uvx vulture . --min-confidence 80 --exclude .venv,venv,node_modules,build,dist
  if [ -f "$d/requirements.txt" ]; then
    run "$p pip-audit" "$d" uvx pip-audit -r requirements.txt
  else
    run "$p pip-audit" "$d" uvx pip-audit .
  fi
}

rust_sweep() {
  local d=$1 p="rust:$1"
  has cargo || {
    skip "$p" "cargo not installed"
    return
  }
  run "$p fmt" "$d" cargo fmt --check
  run "$p clippy" "$d" cargo clippy --all-targets --all-features
  if cargo audit --version >/dev/null 2>&1; then
    run "$p audit" "$d" cargo audit
  else
    skip "$p audit" "cargo-audit not installed"
  fi
}

in_workspace() {
  local dir=$1
  while [ "$dir" != . ]; do
    case $dir in */*) dir=${dir%/*} ;; *) dir=. ;; esac
    [ -f "$dir/Cargo.toml" ] && return 0
  done
  return 1
}

while IFS= read -r d; do go_sweep "$d"; done < <(manifest_dirs 'go\.mod')
while IFS= read -r d; do js_sweep "$d"; done < <(manifest_dirs 'package\.json')
while IFS= read -r d; do py_sweep "$d"; done < <(manifest_dirs 'pyproject\.toml|setup\.py|requirements\.txt')
while IFS= read -r d; do in_workspace "$d" || rust_sweep "$d"; done < <(manifest_dirs 'Cargo\.toml')

sh=()
while IFS= read -r f; do sh+=("$f"); done < <(grep -E '\.(sh|bash)$' <<<"$files")
if [ ${#sh[@]} -gt 0 ]; then
  if has shellcheck; then
    run "sh shellcheck" . shellcheck "${sh[@]}"
  elif has uvx; then
    run "sh shellcheck" . uvx --from shellcheck-py shellcheck "${sh[@]}"
  else
    skip "sh shellcheck" "shellcheck and uv not installed"
  fi
fi

uncovered=$(grep -oE '\.(java|kt|kts|swift|rb|php|cs|c|cc|cpp|h|hpp|m|mm|scala|ex|exs|dart|lua|zig|vue|svelte)$' <<<"$files" |
  sort | uniq -c | awk '{ printf "%s%s (%d files)", sep, $2, $1; sep = ", " }')
[ -n "$uncovered" ] && note "uncovered ${uncovered}: find and run that ecosystem's standard tools"
exit 0
