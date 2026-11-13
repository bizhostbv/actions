# build-multiarch

File: `.github/workflows/build-multiarch.yml` (reusable, `workflow_call`).

## What it does

Builds one image for `linux/amd64` and `linux/arm64` and pushes it as a single multi-arch tag.
Use it for images that have no Helm chart (base images, tools). Each architecture is built natively,
without QEMU, on its own self-hosted runner.

## Inputs

| Name | Required | Type | Default | Meaning |
|---|---|---|---|---|
| `image` | yes | string | | `<project>/<name>`, lowercase, e.g. `myproject/myimage` |
| `tag` | yes | string | | Image tag, e.g. `1.4.0` |
| `registry` | no | string | `registry.k8s-bizhost.nl` | Registry host, optionally with a port |
| `dockerfile` | no | string | `Dockerfile` | Path to the Dockerfile |
| `context` | no | string | `.` | Build context |
| `build_args` | no | string | `''` | Space-separated `KEY=VALUE` pairs, passed as `--build-arg` |
| `immutable` | no | boolean | `true` | Fail when `<image>:<tag>` already exists |

## Secrets

| Name | Required | Meaning |
|---|---|---|
| `registry_username` | no | Registry login for the push |
| `registry_password` | no | Registry password for the push |

Without these two secrets the push relies on a registry login that is already stored on the runner.

## Outputs

| Name | Meaning |
|---|---|
| `image` | `<registry>/<image>:<tag>` |
| `digest` | Digest of the manifest list |

## How it works

Workflow settings: `permissions: contents: read`; `concurrency` group
`build-multiarch-<repository>-<image>-<tag>` with `cancel-in-progress: false`. Registry auth comes
from the secrets or the runner, never from `GITHUB_TOKEN`.

Job `build`, a matrix of two legs with `fail-fast: true`:

| Leg | `runs-on` |
|---|---|
| amd64 | `[self-hosted, harbor-builder]` |
| arm64 | `[self-hosted, harbor-builder-arm64]` |

Steps in each leg:

1. Check out the repository.
2. Validate `registry`, `image` and `tag` against fixed patterns (they end up in registry references).
3. When `immutable` is true: `skopeo inspect` on `<registry>/<image>:<tag>`; fail if it exists.
4. Build with `buildah bud --layers --isolation chroot`, one `--build-arg` per entry of `build_args`.
   Check that the built image has the architecture of the leg; fail otherwise.
5. Push to a local OCI layout, then `skopeo copy --preserve-digests` to `<registry>/<image>@<digest>`.
   The half is pushed by digest, without a tag. The digest is written to the job output
   `digest_amd64` or `digest_arm64`.

Job `manifest` (`needs: build`, `runs-on: [self-hosted, harbor-builder]`):

1. Create a manifest list with `buildah manifest`, add both digests (each must match `sha256:` plus 64 hex characters).
2. Push it as `<registry>/<image>:<tag>`.
3. Read the pushed manifest with `skopeo inspect --raw` and fail unless it lists exactly `amd64,arm64`.
4. Set the outputs `image` and `digest` and write a line to the step summary.

The only tag that exists is `<tag>`; each node pulls its own architecture from it.

`k8s-release-chart.yml` builds the same way inline. The "Build & push" steps of both are kept in sync.

## Example

```yaml
jobs:
  image:
    uses: bizhostbv/actions/.github/workflows/build-multiarch.yml@v3
    with:
      image: myproject/myimage
      tag: 22.4.0
      # registry: harbor.k8s-hotel.nl
    secrets:
      registry_username: ${{ secrets.REGISTRY_USERNAME }}
      registry_password: ${{ secrets.REGISTRY_PASSWORD }}
```
