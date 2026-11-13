# ci-checks

File: `.github/workflows/ci-checks.yml` (reusable, `workflow_call`).

## What it does

A lint, test and SAST gate for Node and PHP apps. It is fail-closed: any red step blocks the merge or
the build. Call it on pull requests and branch pushes, and as a `needs:` job before a release build.

## Inputs

| Name | Required | Type | Default | Meaning |
|---|---|---|---|---|
| `stack` | yes | string | | `node` or `php` |
| `node_version` | no | string | `"22"` | Node version for `actions/setup-node` |
| `php_version` | no | string | `"8.3"` | PHP version for `shivammathur/setup-php` |
| `runs_on` | no | string | `"ubuntu-latest"` | Runner label for the job |
| `workdir` | no | string | `"."` | Working directory of every `run` step |
| `db` | no | string | `""` | `""` or `mysql`. With `mysql` (and `stack: php`) a throwaway MySQL container is started |
| `db_image` | no | string | `"mysql:8.4"` | Image of the test database |
| `db_name` | no | string | `"app_test"` | `MYSQL_DATABASE` |
| `db_user` | no | string | `"app"` | `MYSQL_USER` |
| `db_password` | no | string | `"app"` | `MYSQL_PASSWORD` |
| `db_host_alias` | no | string | `""` | Name added to `/etc/hosts` pointing at `127.0.0.1`, to match the host in the app's forced `DATABASE_URL` |

The schema of the test database is the app's responsibility (for example `tests/bootstrap.php` running `doctrine:schema:update`).

## Secrets

None.

## Outputs

None.

## How it works

Workflow settings: `permissions: contents: read`. One job, `checks`, on `runs-on: ${{ inputs.runs_on }}`,
with `working-directory` set to `workdir`. Steps in order:

1. Check out the repository.
2. `stack: node`: set up Node with the npm cache, then `npm ci`, `npm run lint`, `npm test --if-present`, `npm run build --if-present`.
3. `stack: php` and `db: mysql`: `docker run` a MySQL container named `ci-mysql` on port 3306 with root password `root` and the
   `db_*` values; optionally add the `db_host_alias` line to `/etc/hosts`; wait up to 60 times 2 seconds for `mysqladmin ping`.
4. `stack: php`: set up PHP with Composer, then `composer install`. If a Composer `lint` script exists it runs
   `composer run-script lint`, otherwise `vendor/bin/phpstan analyse`. Then `vendor/bin/phpunit`.
5. For both stacks: SAST with `semgrep/semgrep-action`, config `p/ci`.

## Example

```yaml
jobs:
  checks:
    uses: bizhostbv/actions/.github/workflows/ci-checks.yml@v3
    with:
      stack: php
      db: mysql
      db_host_alias: db
```

This workflow needs no secrets, so the caller passes none.
