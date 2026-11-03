#!/usr/bin/env bash
# Plain test runner for deployflow. No framework, no network: skopeo, buildah, helm and curl are
# stubs on PATH, git talks to local bare repos. Works on bash 3.2 (macOS) and bash 5.
# Needs git, yq (mikefarah v4) and jq on the host.
# Usage: bash deployflow/test/run.sh
HERE=$(cd "$(dirname "$0")" && pwd)
DF="$HERE/../bin/deployflow"
for t in git yq jq; do command -v "$t" >/dev/null || { echo "missing tool: $t"; exit 2; }; done

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
S="$T/stubs"; mkdir -p "$S"
export STUB_DIR="$S" STUB_LOG="$T/stub.log"
export PATH="$S:$PATH"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_TERMINAL_PROMPT=0
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# --- stubs ---------------------------------------------------------------------------------
cat > "$S/skopeo" <<'X'
#!/bin/sh
echo "skopeo $*" >> "$STUB_LOG"
raw=0; ref=""
for a in "$@"; do case $a in --raw) raw=1;; docker://*) ref=${a#docker://};; esac; done
[ "$1" = inspect ] || exit 0
grep -qxF "$ref" "$STUB_DIR/exists" 2>/dev/null || exit 1
if [ $raw = 1 ] && [ -f "$STUB_DIR/manifest.json" ]; then cat "$STUB_DIR/manifest.json"; else echo '{}'; fi
X
cat > "$S/buildah" <<'X'
#!/bin/sh
echo "buildah $*" >> "$STUB_LOG"
case $1 in
  inspect) echo "${STUB_ARCH:-amd64}";;
  push) while [ $# -gt 0 ]; do [ "$1" = --digestfile ] && echo "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" > "$2"; shift; done;;
esac
exit 0
X
cat > "$S/helm" <<'X'
#!/bin/sh
echo "helm $*" >> "$STUB_LOG"
if [ "$1" = package ]; then
  chart=$2; shift 2; ver=""; dir=""
  while [ $# -gt 0 ]; do case $1 in --version) ver=$2;; -d) dir=$2;; esac; shift; done
  cat "$chart/values.yaml" >> "$STUB_LOG"
  : > "$dir/$(sed -n 's/^name: //p' "$chart/Chart.yaml")-$ver.tgz"
fi
exit 0
X
cat > "$S/curl" <<'X'
#!/bin/sh
out=""; url=""
while [ $# -gt 0 ]; do case $1 in -o) out=$2; shift;; -w|-H) shift;; http*) url=$1;; esac; shift; done
echo "curl $url" >> "$STUB_LOG"
[ -z "$STUB_CURL_FAIL" ] || exit 7
printf '%s' "$STUB_CURL_BODY" > "$out"
printf '%s' "${STUB_CURL_CODE:-200}"
X
chmod +x "$S"/*

# --- tiny framework ------------------------------------------------------------------------
PASS=0; FAIL=0
assert() { # assert <description> <command...>
  local d=$1; shift
  if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); echo "ok   $d"
  else FAIL=$((FAIL+1)); echo "FAIL $d"; echo "     rc=${RC:-} out=$(printf '%s' "${OUT:-}" | head -c 400)"; fi
}
run() { OUT=$(cd "${RUNDIR:-$PWD}" && "$@" 2>&1) && RC=0 || RC=$?; }
has() { case $1 in *"$2"*) return 0;; esac; return 1; }
reset() { : > "$STUB_LOG"; : > "$S/exists"; rm -f "$S/manifest.json"; unset STUB_CURL_FAIL STUB_CURL_BODY STUB_CURL_CODE STUB_ARCH; RUNDIR=; }
art() { echo "reg.example/proj/app:$1" >> "$S/exists"; echo "reg.example/proj/charts/app:$1" >> "$S/exists"; }
ENV0=(PROJECT=proj APP=app REGISTRY=reg.example)

# --- version -------------------------------------------------------------------------------
c() { git -C "$APPDIR" commit -q --allow-empty -m "$@"; }
mkapp() { APPDIR=$(mktemp -d "$T/app.XXXX"); git init -q -b main "$APPDIR"; c "chore: init"; }
vtest() { # vtest <desc> <expected-version|none> <tag-or-empty> <commit subject>...
  local desc=$1 want=$2 tag=$3; shift 3
  reset; mkapp; [ -z "$tag" ] || git -C "$APPDIR" tag "$tag"
  local s; for s in "$@"; do c "$s"; done
  RUNDIR=$APPDIR; run env DEPLOYFLOW_OUTPUT="$APPDIR.out" "$DF" version
  assert "version: $desc -> $want" test "$OUT" = "$want"
  if [ "$want" = none ]; then
    assert "version: $desc sets released=false" grep -qx 'released=false' "$APPDIR.out"
    assert "version: $desc creates no tag" test "$(git -C "$APPDIR" tag -l | grep -c .)" = "$([ -z "$tag" ] && echo 0 || echo 1)"
  else
    assert "version: $desc writes outputs" grep -qx "version=$want" "$APPDIR.out"
    assert "version: $desc released=true" grep -qx 'released=true' "$APPDIR.out"
    assert "version: $desc tag $want exists without v" test "$(git -C "$APPDIR" tag -l "$want")" = "$want"
    assert "version: $desc tag is annotated" test "$(git -C "$APPDIR" cat-file -t "$want")" = tag
  fi
}
vtest "no tags, feat" 0.1.0 "" "feat: a"
vtest "feat bumps minor (v tag)" 1.3.0 v1.2.3 "feat(x): a" "fix: b"
vtest "fix bumps patch (v tag)" 1.2.4 v1.2.3 "fix: a" "chore: b"
vtest "fix bumps patch (tag without v)" 1.2.4 1.2.3 "fix: a"
vtest "feat bumps minor (tag without v)" 1.3.0 1.2.3 "feat: a"
vtest "type! is major" 2.0.0 1.2.3 "feat(api)!: drop it"
vtest "BREAKING CHANGE body is major" 2.0.0 1.2.3 "fix: a

BREAKING CHANGE: gone"
vtest "0.x breaking is minor" 0.5.0 0.4.2 "feat!: a"
vtest "only chore/docs" none 1.2.3 "chore: a" "docs: b"
vtest "nothing since tag" none 1.2.3
# numeric ordering across v/no-v and 1.9 vs 1.10
reset; mkapp; git -C "$APPDIR" tag v1.9.0; c "chore: x"; git -C "$APPDIR" tag 1.10.0; c "fix: y"
RUNDIR=$APPDIR; run "$DF" version
assert "version: picks 1.10.0 over v1.9.0 as base" test "$OUT" = 1.10.1

# --- push-tag ------------------------------------------------------------------------------
reset; mkapp; git init -q --bare -b main "$T/origin.git"; git -C "$APPDIR" remote add origin "$T/origin.git"
RUNDIR=$APPDIR; run env VERSION=1.0.0 "$DF" push-tag
assert "push-tag creates and pushes tag 1.0.0" test "$(git -C "$T/origin.git" tag -l)" = 1.0.0
run env VERSION=1.0.0 "$DF" push-tag
assert "push-tag is idempotent when tag already on remote" test "$RC" -eq 0
run env VERSION=v1 "$DF" push-tag
assert "push-tag rejects a bad version" test "$RC" -ne 0

# --- check-title ---------------------------------------------------------------------------
for t in "feat: add x" "fix(api): y" "feat(api)!: z" "revert: w" "ci: q"; do
  reset; run env TITLE="$t" "$DF" check-title; assert "check-title accepts '$t'" test "$RC" -eq 0
done
for t in "Update stuff" "feat:no space" "feat: " "feature: x" "Feat: x" ""; do
  reset; run env TITLE="$t" "$DF" check-title
  assert "check-title rejects '$t'" test "$RC" -eq 1
  assert "check-title explains '$t'" has "$OUT" "conventional"
done

# --- guard-immutable -----------------------------------------------------------------------
reset; run env "${ENV0[@]}" VERSION=1.0.0 "$DF" guard-immutable
assert "guard-immutable: free version passes" test "$RC" -eq 0
reset; echo "reg.example/proj/app:1.0.0" >> "$S/exists"; run env "${ENV0[@]}" VERSION=1.0.0 "$DF" guard-immutable
assert "guard-immutable: existing image fails" test "$RC" -eq 1
assert "guard-immutable: names the image" has "$OUT" "image reg.example/proj/app:1.0.0 already exists"
reset; echo "reg.example/proj/charts/app:1.0.0" >> "$S/exists"; run env "${ENV0[@]}" VERSION=1.0.0 "$DF" guard-immutable
assert "guard-immutable: existing chart fails" test "$RC" -eq 1
assert "guard-immutable: chart check uses --raw" grep -q 'inspect --raw docker://reg.example/proj/charts/app:1.0.0' "$STUB_LOG"
reset; run env "${ENV0[@]}" APP=Bad_App VERSION=1.0.0 "$DF" guard-immutable
assert "guard-immutable: invalid APP charset fails" test "$RC" -eq 1
reset; run env "${ENV0[@]}" VERSION=1.0 "$DF" guard-immutable
assert "guard-immutable: invalid version fails" test "$RC" -eq 1
reset; run env "${ENV0[@]}" VERSION=1.0.0 REGISTRY_USER=u REGISTRY_PASSWORD=p "$DF" guard-immutable
assert "registry login happens when credentials are given" grep -q 'skopeo login -u u --password-stdin reg.example' "$STUB_LOG"

# --- build ---------------------------------------------------------------------------------
reset; export STUB_ARCH=arm64; run env "${ENV0[@]}" VERSION=1.0.0 ARCH=arm64 GIT_SHA=abc123 DEPLOYFLOW_OUTPUT="$T/b.out" "$DF" build
assert "build: succeeds" test "$RC" -eq 0
assert "build: writes digest_arm64 output" grep -qx 'digest_arm64=sha256:a\{64\}' "$T/b.out"
assert "build: uses chroot isolation" grep -q -- '--isolation chroot' "$STUB_LOG"
assert "build: passes build args" grep -q 'APP_BUILD_SHA=abc123.*APP_BUILD_VERSION=1.0.0' "$STUB_LOG"
assert "build: pushes by digest" grep -q 'skopeo copy --preserve-digests .* docker://reg.example/proj/app@sha256:' "$STUB_LOG"
reset; export STUB_ARCH=amd64; run env "${ENV0[@]}" VERSION=1.0.0 ARCH=arm64 GIT_SHA=abc "$DF" build
assert "build: wrong arch on the runner fails" test "$RC" -eq 1
assert "build: wrong arch message" has "$OUT" "built amd64 on the arm64 runner"
assert "build: wrong arch pushes nothing" test -z "$(grep 'skopeo copy' "$STUB_LOG")"
reset; run env "${ENV0[@]}" VERSION=1.0.0 ARCH=s390x GIT_SHA=abc "$DF" build
assert "build: unsupported ARCH fails" test "$RC" -eq 1
reset; export STUB_ARCH=amd64; run env "${ENV0[@]}" VERSION=1.0.0 ARCH=amd64 GIT_SHA=abc NPM_TOKEN=s3cret "$DF" build
assert "build: NPM_TOKEN becomes a build secret, never printed" sh -c "grep -q -- '--secret id=npm_token' '$STUB_LOG' && ! printf '%s' '$OUT' | grep -q s3cret"

# --- publish -------------------------------------------------------------------------------
D1=sha256:1111111111111111111111111111111111111111111111111111111111111111
D2=sha256:2222222222222222222222222222222222222222222222222222222222222222
CH="$T/chart"; mkdir -p "$CH"; printf 'name: app\nversion: 0.0.0\n' > "$CH/Chart.yaml"; printf 'image:\n  tag: latest\n' > "$CH/values.yaml"
pub() { run env "${ENV0[@]}" VERSION=1.0.0 DIGEST_AMD64=$D1 DIGEST_ARM64=$D2 CHART_DIR="$CH" "$@" "$DF" publish; }
reset; art 1.0.0; echo '{"manifests":[{"platform":{"architecture":"amd64"}},{"platform":{"architecture":"arm64"}}]}' > "$S/manifest.json"; pub
assert "publish: succeeds with both arches" test "$RC" -eq 0
assert "publish: joins both digests" sh -c "grep -c 'buildah manifest add' '$STUB_LOG' | grep -qx 2"
assert "publish: pushes manifest list :1.0.0" grep -q 'buildah manifest push --all .* docker://reg.example/proj/app:1.0.0' "$STUB_LOG"
assert "publish: packages with version and app-version" grep -q 'helm package .* --version 1.0.0 --app-version 1.0.0' "$STUB_LOG"
assert "publish: bakes image.tag into the packaged chart" grep -qx '  tag: 1.0.0' "$STUB_LOG"
assert "publish: leaves the source chart untouched" grep -qx '  tag: latest' "$CH/values.yaml"
assert "publish: pushes chart to charts path" grep -q 'helm push .*app-1.0.0.tgz oci://reg.example/proj/charts' "$STUB_LOG"
reset; art 1.0.0; echo '{"manifests":[{"platform":{"architecture":"amd64"}}]}' > "$S/manifest.json"; pub
assert "publish: missing arm64 fails" test "$RC" -eq 1
assert "publish: missing arm64 pushes no chart" test -z "$(grep 'helm push' "$STUB_LOG")"
reset; art 1.0.0; echo '{"manifests":[{"platform":{"architecture":"amd64"}},{"platform":{"architecture":"arm64"}}]}' > "$S/manifest.json"
run env "${ENV0[@]}" APP=other VERSION=1.0.0 DIGEST_AMD64=$D1 DIGEST_ARM64=$D2 CHART_DIR="$CH" "$DF" publish
assert "publish: chart name must equal APP" test "$RC" -eq 1
pub DIGEST_ARM64=nonsense
assert "publish: bad digest fails" test "$RC" -eq 1

# --- gitops fixtures -----------------------------------------------------------------------
ACC=gwsn/app/argocd/acceptance.yaml; PROD=gwsn/app/argocd/production.yaml
appfile() { mkdir -p "$(dirname "$1")"; printf 'spec:\n  sources:\n    - repoURL: x\n      targetRevision: %s\n' "$2" > "$1"; }
mkgitops() { # mkgitops <acc> <prod history, oldest first...>
  local acc=$1; shift
  G=$(mktemp -d "$T/gitops.XXXX"); git init -q --bare -b main "$G/remote.git"; git clone -q "$G/remote.git" "$G/w" 2>/dev/null
  appfile "$G/w/$ACC" "$acc"
  local v; for v in "$@"; do appfile "$G/w/$PROD" "$v"; git -C "$G/w" add -A; git -C "$G/w" commit -q -m "prod $v"; done
  git -C "$G/w" push -q origin HEAD:main
}
rrev() { git -C "$G/remote.git" show "main:$1" | yq e '.spec.sources[0].targetRevision' -; }
rmsg() { git -C "$G/remote.git" log -1 --format=%B main; }
rcount() { git -C "$G/remote.git" rev-list --count main; }
GENV=(APP=app VERSION=1.1.0 GITOPS_ACC_FILE="$ACC" RUN_URL=https://ci.example/run/7)

# --- gitops-acc ----------------------------------------------------------------------------
reset; mkgitops 1.0.0 1.0.0; run env "${GENV[@]}" GITOPS_REPO="$G/remote.git" "$DF" gitops-acc
assert "gitops-acc: forward bump succeeds" test "$RC" -eq 0
assert "gitops-acc: forward bump writes 1.1.0" test "$(rrev $ACC)" = 1.1.0
assert "gitops-acc: commit subject" test "$(rmsg | head -1)" = "release(app): 1.1.0 to acceptance"
assert "gitops-acc: commit body has run url" has "$(rmsg)" "https://ci.example/run/7"
reset; mkgitops 1.1.0 1.0.0; n=$(rcount); run env "${GENV[@]}" GITOPS_REPO="$G/remote.git" "$DF" gitops-acc
assert "gitops-acc: equal version is a skip" sh -c "test $RC -eq 0 && test $(rcount) -eq $n"
assert "gitops-acc: equal says skip" has "$OUT" "skip"
reset; mkgitops 2.0.0 1.0.0; n=$(rcount); run env "${GENV[@]}" GITOPS_REPO="$G/remote.git" "$DF" gitops-acc
assert "gitops-acc: backward is a skip, exit 0, no commit" sh -c "test $RC -eq 0 && test $(rcount) -eq $n && test $(rrev $ACC) = 2.0.0" 
reset; mkgitops 1.9.0 1.0.0; run env "${GENV[@]}" VERSION=1.10.0 GITOPS_REPO="$G/remote.git" "$DF" gitops-acc
assert "gitops-acc: 1.9.0 -> 1.10.0 goes forward" test "$(rrev $ACC)" = 1.10.0
reset; mkgitops 1.0.0 1.0.0; run env "${GENV[@]}" GITOPS_ACC_FILE=nope.yaml GITOPS_REPO="$G/remote.git" "$DF" gitops-acc
assert "gitops-acc: missing file fails" test "$RC" -eq 1
# push rejected once by the remote: the rebase retry must get it through
reset; mkgitops 1.0.0 1.0.0
# shellcheck disable=SC2016
printf '#!/bin/sh\nc=$(cat "$0.n" 2>/dev/null || echo 0); echo $((c+1)) > "$0.n"; [ "$c" -ge 1 ] || exit 1\n' > "$G/remote.git/hooks/pre-receive"; chmod +x "$G/remote.git/hooks/pre-receive"
run env "${GENV[@]}" GITOPS_REPO="$G/remote.git" "$DF" gitops-acc
assert "gitops-acc: push retried after one rejection" sh -c "test $RC -eq 0 && test $(rrev $ACC) = 1.1.0"
reset; mkgitops 1.0.0 1.0.0; printf '#!/bin/sh\nexit 1\n' > "$G/remote.git/hooks/pre-receive"; chmod +x "$G/remote.git/hooks/pre-receive"
run env "${GENV[@]}" GITOPS_REPO="$G/remote.git" "$DF" gitops-acc
assert "gitops-acc: gives up after 3 attempts" sh -c "test $RC -eq 1" 
assert "gitops-acc: gives up message" has "$OUT" "after 3 attempts"

# --- release-prod --------------------------------------------------------------------------
setup_rp() { # setup_rp <acc> <prod history...>
  reset; mkgitops "$@"; export STUB_CURL_CODE=200 STUB_CURL_BODY='{"state":"active"}'
  BASE=(PROJECT=proj APP=app REGISTRY=reg.example ORG=acme ACTOR=alice ACTOR_ID=42 API_TOKEN=tok DEPLOYFLOW_PROVIDER=github
        GITHUB_API_URL=https://gh.example GITLAB_API_URL=https://gl.example/api/v4
        GITOPS_REPO="$G/remote.git" GITOPS_ACC_FILE="$ACC" GITOPS_PROD_FILE="$PROD" RUN_URL=https://ci.example/run/9)
  N0=$(rcount)
}
rp() { run env "${BASE[@]}" "$@" "$DF" release-prod; }
untouched() { test "$(rcount)" -eq "$N0"; }

setup_rp 1.2.0 1.1.0; export STUB_CURL_CODE=404; art 1.2.0; rp
assert "release-prod: github non-member refused" test "$RC" -eq 1
assert "release-prod: github non-member message" has "$OUT" "not an active member of acme/release-admins"
assert "release-prod: github non-member leaves gitops untouched" untouched
assert "release-prod: github membership URL" grep -q 'curl https://gh.example/orgs/acme/teams/release-admins/memberships/alice' "$STUB_LOG"
setup_rp 1.2.0 1.1.0; art 1.2.0; export STUB_CURL_BODY='{"state":"pending"}'; rp
assert "release-prod: github pending membership refused" sh -c "test $RC -eq 1"
setup_rp 1.2.0 1.1.0; art 1.2.0; export STUB_CURL_CODE=500; rp
assert "release-prod: API error refused" test "$RC" -eq 1
assert "release-prod: API error leaves gitops untouched" untouched
setup_rp 1.2.0 1.1.0; art 1.2.0; export STUB_CURL_FAIL=1; rp
assert "release-prod: unreachable API refused" test "$RC" -eq 1
setup_rp 1.2.0 1.1.0; art 1.2.0; export STUB_CURL_CODE=200 STUB_CURL_BODY=''; rp
assert "release-prod: empty 200 body refused" test "$RC" -eq 1
setup_rp 1.2.0 1.1.0; art 1.2.0; export STUB_CURL_CODE=404; rp DEPLOYFLOW_PROVIDER=gitlab ORG=acme/sub
assert "release-prod: gitlab non-member refused" test "$RC" -eq 1
assert "release-prod: gitlab URL encodes the group path" grep -q 'curl https://gl.example/api/v4/groups/acme%2Fsub%2Frelease-admins/members/42' "$STUB_LOG"
setup_rp 1.2.0 1.1.0; art 1.2.0; export STUB_CURL_CODE=200 STUB_CURL_BODY='{}'; rp DEPLOYFLOW_PROVIDER=gitlab
assert "release-prod: gitlab 200 without access_level refused" test "$RC" -eq 1
setup_rp 1.2.0 1.1.0; art 1.2.0; export STUB_CURL_CODE=200 STUB_CURL_BODY='{"access_level":30}'; rp DEPLOYFLOW_PROVIDER=gitlab
assert "release-prod: gitlab member ok" sh -c "test $RC -eq 0 && test $(rrev $PROD) = 1.2.0"
rp DEPLOYFLOW_PROVIDER=bitbucket
assert "release-prod: unknown provider refused" test "$RC" -eq 1

OK='{"state":"active"}'
setup_rp 1.2.0 1.0.0 1.1.0; art 1.2.0; export STUB_CURL_CODE=200 STUB_CURL_BODY="$OK"; rp
assert "release-prod: member ok" test "$RC" -eq 0
assert "release-prod: version comes from the acc file" test "$(rrev $PROD)" = 1.2.0
assert "release-prod: commit subject" test "$(rmsg | head -1)" = "release(app): 1.2.0 to production by alice"
assert "release-prod: commit body has run url" has "$(rmsg)" "https://ci.example/run/9"
assert "release-prod: acc file is not touched" test "$(rrev $ACC)" = 1.2.0
setup_rp 1.2.0 1.1.0; art 1.2.0; rp VERSION=9.9.9 
assert "release-prod: a typed VERSION is ignored" test "$(rrev $PROD)" = 1.2.0
setup_rp 1.2.0 1.1.0; echo "reg.example/proj/charts/app:1.2.0" >> "$S/exists"; rp
assert "release-prod: missing image refused" sh -c "test $RC -eq 1" 
assert "release-prod: missing image message" has "$OUT" "image reg.example/proj/app:1.2.0 does not exist"
assert "release-prod: missing image leaves gitops untouched" untouched
setup_rp 1.2.0 1.1.0; echo "reg.example/proj/app:1.2.0" >> "$S/exists"; rp
assert "release-prod: missing chart refused" has "$OUT" "chart reg.example/proj/charts/app:1.2.0 does not exist"
assert "release-prod: chart check uses --raw" grep -q 'inspect --raw docker://reg.example/proj/charts/app:1.2.0' "$STUB_LOG"
setup_rp 1.1.0 1.1.0; art 1.1.0; rp
assert "release-prod: same as prod refused" has "$OUT" "is not newer"
setup_rp 1.0.0 1.1.0; art 1.0.0; rp
assert "release-prod: acc older than prod refused" sh -c "test $RC -eq 1" 
assert "release-prod: older leaves gitops untouched" untouched
setup_rp 1.2.0 1.9.0; art 1.2.0; rp
assert "release-prod: 1.2.0 is older than 1.9.0 (numeric compare)" test "$RC" -eq 1
setup_rp 1.10.0 1.9.0; art 1.10.0; rp
assert "release-prod: 1.10.0 is newer than 1.9.0" test "$(rrev $PROD)" = 1.10.0

setup_rp 1.3.0 1.0.0 1.1.0 1.2.0; art 1.1.0; rp ROLLBACK=1.1.0
assert "release-prod: rollback to a former prod version ok" test "$(rrev $PROD)" = 1.1.0
assert "release-prod: rollback commit subject" test "$(rmsg | head -1)" = "rollback(app): 1.1.0 to production by alice"
assert "release-prod: rollback commit body has run url" has "$(rmsg)" "https://ci.example/run/9"
setup_rp 1.3.0 1.0.0 1.1.0 1.2.0; art 1.15.0; rp ROLLBACK=1.15.0
assert "release-prod: rollback to a never-prod version refused" has "$OUT" "never a production version"
assert "release-prod: never-prod leaves gitops untouched" untouched
setup_rp 1.3.0 1.0.0 1.1.0 1.2.0; art 1.1.0; rp ROLLBACK=1.1
assert "release-prod: rollback with a bad version refused" test "$RC" -eq 1
setup_rp 1.3.0 1.0.0 1.1.0 1.2.0; art 1.2.0; rp ROLLBACK=1.2.0
assert "release-prod: rollback to the current version refused" has "$OUT" "not older than production"
setup_rp 1.3.0 1.0.0 1.3.0 1.1.0; art 1.3.0; rp ROLLBACK=1.3.0
assert "release-prod: rollback to a newer (former) version refused" has "$OUT" "not older than production"
assert "release-prod: newer rollback leaves gitops untouched" untouched
setup_rp 1.3.0 1.0.0 1.1.0 1.2.0; rp ROLLBACK=1.1.0
assert "release-prod: rollback with missing artifacts refused" has "$OUT" "does not exist"
setup_rp 1.3.0 1.0.0 1.1.0 1.2.0; art 1.1.0; rp ROLLBACK=1.1.0 STUB_X=1 DEPLOYFLOW_PROVIDER=github ACTOR='eve bad'
assert "release-prod: odd ACTOR refused" test "$RC" -eq 1

echo; echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
