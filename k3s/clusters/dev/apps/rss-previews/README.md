# RSS PR previews

Flux Operator polls open PRs in `kveeti/rss` every 10 minutes. The ResourceSet
renders resources only when the PR author username is exactly `kveeti`.
No label, webhook, GitHub token or custom service is required for this public repo.

Each allowed PR gets `rss-pr-<number>` in the shared `rss-preview` namespace:

- One RSS Deployment and Service, using `veetik/rss:<full-PR-head-SHA>`.
- One fresh CNPG instance with a 1 GiB `local-path` volume, no replica or backup.
- Network rules allowing the app to reach only its own database, DNS and public
  HTTP/HTTPS addresses. Production databases and other preview databases are blocked.

The app uses its database's generated credentials and verifies the database TLS
certificate. Neither the app nor the Flux impersonation account mounts a token.
Flux's account can manage only Services, Deployments, CNPG Clusters and
NetworkPolicies inside `rss-preview`; it cannot read Secrets or change production.

Pushing a new commit changes the image, not the database name. Closing or merging
removes the generated resources. CNPG owns its PVC, and `local-path` uses the
`Delete` reclaim policy. Database contents are disposable. The 1 GiB storage
request is not an enforced filesystem quota with `local-path`.

The ResourceSet does not wait for app readiness, so a failed image build on one
PR does not prevent cleanup of closed PRs. A preview may show ImagePullBackOff
until CI publishes that commit's image. A failed build will not produce a working
preview.

## Image publication

RSS's `.github/workflows/ci.yml` must be deployed alongside this config. It checks
out the PR head rather than GitHub's synthetic merge commit, builds both
architectures and publishes the full SHA tag. Path filters are removed so every
new PR head gets an image, including docs-only commits.

Publishing is limited to same-repository PRs because fork workflows do not receive
the Docker Hub credential. Main builds keep their existing tags. Production's
pinned deployment image and database config are unchanged.

## Access

This first version has no HTTPRoute, DNS or Envoy changes. For PR 123:

```sh
ssh -L 127.0.0.1:9080:127.0.0.1:9080 veeti@192.168.40.9 \
  'sudo -n k3s kubectl port-forward --address 127.0.0.1 -n rss-preview deployment/rss-pr-123 9080:8000'
```

Open http://localhost:9080. Ctrl-C closes the tunnel.

To request a discovery refresh without waiting for the next poll:

```sh
ssh veeti@192.168.40.9 \
  'sudo -n k3s kubectl annotate resourcesetinputprovider rss-prs -n rss-preview reconcile.fluxcd.io/requestedAt="$(date +%s)" --overwrite'
```

## Enable

Open the RSS CI PR first. Its pull-request workflow can publish that PR's head
image before the CI change merges. Once Actions succeeds, merge the `conf` PR to
activate discovery. The `rss-previews` Flux Kustomization installs this directory
after CNPG is ready. Keep the RSS PR open to test its preview, then merge or close
it to check cleanup.

A live validation used two temporary PR inputs and the existing production image
with separate new databases. Both apps became healthy, HTTP returned 200, the
preview account could not read Secrets or modify production, and a network probe
could reach its own database but not another preview or production. Switching to
an untrusted author removed both previews and their PVCs/PVs. The temporary
namespace was removed. This validates the deployment template and cleanup, not a
new CI build or a real PR lifecycle.
