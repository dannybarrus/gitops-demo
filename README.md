# GitOps Demo: ArgoCD + kind

A self-contained, local GitOps setup. No shared playground, no session
timer, no third-party infrastructure to fight with -- just Docker,
`kind`, and a GitHub repo. Tear it down and bring it back up as many
times as needed.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/)
- [kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- This repo, pushed to a GitHub remote

## Setup

```bash
git clone https://github.com/yourname/gitops-demo.git
cd gitops-demo
chmod +x setup.sh teardown.sh
./setup.sh https://github.com/yourname/gitops-demo.git
```

One command, the repo URL as the only argument. Creates the cluster,
installs ArgoCD, waits for it to be ready, points it at the repo, in
that order, each step checked before it runs. A few minutes the first
time (pulling images); seconds after that, since it skips anything
already done.

When it finishes, it prints the ArgoCD admin password and the URLs for
the app and the ArgoCD UI.

## What's actually here

`apps/hello-world/` is the app ArgoCD manages -- an nginx Deployment
serving content from a ConfigMap, so a one-line Git change produces a
visible result rather than something only checkable via logs.
`argocd/hello-world-application.template.yaml` is the Application
definition; `setup.sh` substitutes the real repo URL into it before
applying.

`syncPolicy.automated.selfHeal: true` is the actual point of the whole
exercise. With it set, anything applied directly to the cluster --
`kubectl edit`, `kubectl scale`, anything bypassing Git -- gets
reverted on ArgoCD's next reconciliation pass. Not flagged, not
alerted on: reverted, automatically, with nothing in the loop.

## Confirming it works

```bash
kubectl get pods -l app=hello-world
```

`http://localhost:30080` should show "Version: v1."

**A change through Git:** edit `apps/hello-world/configmap.yaml`,
bump the version string, commit, push. Within ArgoCD's next
reconciliation pass (or force it: `kubectl patch application
hello-world -n argocd --type merge -p
'{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'`),
the page updates. Nothing was run against the cluster directly.

**Drift and self-heal:**

```bash
kubectl scale deployment hello-world --replicas=5
kubectl get deployment hello-world   # wait a few seconds first
```

Replicas land back at 2 on their own.

## Demo sequence

The whole thing runs in about two minutes once it's set up:

1. `./setup.sh https://github.com/dannybarrus/gitops-demo.git` (or skip, if the cluster's already running --
   `kind get clusters` to check)
2. `localhost:30080` -- what's running, what's in Git
3. Edit the ConfigMap, push, refresh the page
4. `kubectl scale --replicas=5`, wait, `kubectl get deployment` --
   the self-heal moment

Worth running through once before showing it live, the same as any
demo. Confirm the four steps above actually work on the machine and
repo being used, not just in theory.

## Notes worth keeping

- **Push vs. pull**: a CI-push model needs deploy credentials reaching
  *into* the target environment. ArgoCD runs inside the cluster and
  only needs read access to Git -- cluster credentials never leave the
  cluster boundary.
- **PR + review, unchanged**: this isn't a replacement for that
  discipline, just a different delivery mechanism on the other end of
  the same git-as-source-of-truth model.
- **Self-healing vs. self-detecting** is the one genuinely new
  capability over an alerting-only setup: drift doesn't just get
  reported, it gets corrected, on every reconciliation pass, with
  nobody acting on anything.

## Tearing down

```bash
./teardown.sh
```

Deletes the kind cluster entirely. Nothing else on the machine is
touched -- everything lived inside that one cluster.
