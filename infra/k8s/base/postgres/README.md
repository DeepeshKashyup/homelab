# postgres/

Shared Postgres instance for all apps on the platform (n8n, the `nlp-to-sql` agent, and whatever comes next), via the [CloudNativePG](https://cloudnative-pg.io/) operator, pinned to `control-plane-01` (most free disk, no GPU contention — same reasoning as Open WebUI and Plex). See [ADR 0015](../../../../docs/decisions/0015-cloudnativepg-single-instance-clusterip.md) for why CloudNativePG, why a single instance, why `ClusterIP`-only, and the backup design.

## Apply

```bash
# 1. One-time, cluster-wide operator install (CRDs + cnpg-system namespace + controller).
#    Unmodified upstream manifest — not vendored here. Run once ever, on control-plane-01.
sudo k3s kubectl apply --server-side -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.30/releases/cnpg-1.30.0.yaml

# 2. Namespace + Cluster
sudo k3s kubectl apply -f infra/k8s/base/postgres/00-namespace.yaml
sudo k3s kubectl apply -f infra/k8s/base/postgres/01-postgres-cluster.yaml
```

Wait for it to come up:

```bash
sudo k3s kubectl get cluster -n postgres -w
sudo k3s kubectl get pods -n postgres
```

Healthy state shows `Cluster in healthy state` and one `postgres-1` pod `Running`.

## Getting credentials

CNPG generates Secrets automatically — nothing is hand-rolled or checked in.

```bash
# App user (bootstrap "app" database)
sudo k3s kubectl get secret postgres-app -n postgres -o jsonpath='{.data.password}' | base64 -d

# Superuser (used internally by the backup CronJob only — see below)
sudo k3s kubectl get secret postgres-superuser -n postgres -o jsonpath='{.data.password}' | base64 -d
```

## Connecting

**No NodePort** — Postgres is backend-only infrastructure, reached in-cluster via the `postgres-rw` (read/write, primary), `postgres-ro` (read-only replicas — none yet, single instance), and `postgres-r` (any instance) Services CNPG creates automatically. Apps running in-cluster should use `postgres-rw.postgres.svc.cluster.local:5432`.

For ad-hoc admin access from the Dell G5, tunnel in instead of exposing the DB on the LAN:

```bash
sudo k3s kubectl port-forward -n postgres svc/postgres-rw 5432:5432
# then, from another terminal / another machine reaching control-plane-01:
psql -h localhost -U app -d app
```

## Adding a database for a new app

Don't reuse the bootstrap `app` database for a second app — give each app its own database (and ideally its own role) via CNPG's declarative `Database` CRD:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Database
metadata:
  name: n8n
  namespace: postgres
spec:
  cluster:
    name: postgres
  name: n8n
  owner: n8n
```

(CNPG reconciles the actual `CREATE DATABASE`/`CREATE ROLE` inside the cluster — no manual `psql` needed. Check the installed operator's version docs for the exact `Database`/`DatabaseRole` CRD fields if this doesn't apply cleanly; CNPG has been actively adding declarative role/database management across recent releases.)

### Gotcha: `Database` stuck on "source database template1 is being accessed by other users"

Hit migrating Open WebUI and Grafana to their own databases (2026-08-30): both `Database` resources sat with `APPLIED: false` for 5+ minutes straight, `kubectl describe` showing `ERROR: source database "template1" is being accessed by other users (SQLSTATE 55006)` — `CREATE DATABASE` refuses to run while *any* other session is connected to its template, and this isn't a one-off transient blip that clears itself on the next reconcile.

Found the actual holder via `kubectl exec -n postgres postgres-1 -- psql -U postgres -c "SELECT pid, usename, datname, state, query FROM pg_stat_activity WHERE datname = 'template1';"` — a long-idle connection (`SELECT 1;`, likely a stray health-check/liveness-probe connection) sitting on `template1`. Cleared it with `SELECT pg_terminate_backend(<pid>);`, and the pending `Database` resources reconciled successfully within seconds on CNPG's next pass.

If a new `Database` resource ever sits stuck on this same error, check `pg_stat_activity` for `template1` first before assuming the manifest is wrong. A more permanent fix worth trying next time: set `spec.template: template0` on the `Database` CRD (a field CNPG supports) — `template0` is never used for direct connections in normal operation, so it shouldn't be vulnerable to this at all. Not yet applied retroactively to `n8n`/`openwebui`/`grafana`'s existing `Database` resources since `template` "cannot be changed" per the CRD's own field description (would need a fresh `Database` object, not an edit).

## Backups

Data lives on `control-plane-01`'s local disk (`local-path` StorageClass) — plain node-local storage, **not redundant**. If that disk or node is lost, the data is lost unless it's been backed up first. That's what `02-postgres-backup-cronjob.yaml` is for.

**One-time OS-level prerequisite on `control-plane-01`** (done outside Kubernetes, before applying the CronJob) — done 2026-08-24:

1. Identified the external USB drive: `lsblk` / `sudo blkid` found `/dev/sdb1`, labeled "Backup Plus", **exFAT**, UUID `5EF4-3CF2` — already holding other personal data (photos, GoPro footage, an OneDrive backup, etc.), so it was **not** reformatted.
2. Mounted as-is (exFAT, not reformatted to ext4) at a stable path by UUID via `/etc/fstab`, with `nofail` so a boot doesn't hang if the drive isn't plugged in, and permissive `uid=0,gid=0,umask=000` mount options since exFAT has no native POSIX permissions (the CronJob's container doesn't necessarily run as the same UID as the host):
   ```
   UUID=5EF4-3CF2  /mnt/backup-plus  exfat  defaults,nofail,uid=0,gid=0,umask=000  0  0
   ```
3. `sudo mkdir -p /mnt/backup-plus && sudo mount -a`, confirmed with `df -h /mnt/backup-plus`.
4. Created a dedicated subfolder rather than writing into the drive's root: `sudo mkdir -p /mnt/backup-plus/postgres-backups` — this is what the CronJob's `hostPath` actually points at.

If this drive is ever swapped for a different one, redo these four steps with the new drive's UUID and update `02-postgres-backup-cronjob.yaml`'s `hostPath.path` if the subfolder name changes.

Then apply the CronJob:

```bash
sudo k3s kubectl apply -f infra/k8s/base/postgres/02-postgres-backup-cronjob.yaml
```

It runs weekly (Sunday 03:00), dumping every database + role on the instance (`pg_dumpall`, needs `enableSuperuserAccess: true` on the Cluster) to a gzip'd, timestamped file under `/mnt/postgres-backups`, and prunes dumps older than 8 weeks.

**Test it immediately rather than waiting a week:**

```bash
sudo k3s kubectl create job --from=cronjob/postgres-backup -n postgres postgres-backup-test
sudo k3s kubectl logs -n postgres job/postgres-backup-test
ls -lh /mnt/backup-plus/postgres-backups   # on control-plane-01
```

**Restoring** from one of these dumps (disaster-recovery case, e.g. after a node wipe): stand the Cluster back up empty (steps above), port-forward in, then `gunzip -c postgres-all-<date>.sql.gz | psql -h localhost -U app -d app` (needs superuser creds for a full `pg_dumpall` restore — pipe to `postgres` db via the superuser instead of `app` if restoring roles/other databases too).

This is a logical (SQL-text) backup, not CNPG's native physical backup + point-in-time recovery (`barman-cloud`) — that needs an S3-compatible target (e.g. a future MinIO instance), which doesn't exist on this platform yet. Upgrading to that is a tracked backlog item, not built today.

## First-deploy verification checklist

- `sudo k3s kubectl get cluster -n postgres` shows healthy, one pod `Running`.
- Can retrieve the `app` password and connect via `port-forward` + `psql`.
- Manually triggered backup Job completes and a `.sql.gz` file actually lands under `/mnt/postgres-backups`.

Update this README once verified — note here if anything needed correcting (CNPG version/CRD field names move fast; pin to a specific operator release if `release-1.30` gets superseded and behavior changes).
