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

Start a watch in one terminal *before* triggering anything, so the
whole lifecycle plays out live instead of comparing two static
snapshots:

```bash
kubectl get pods -l app=hello-world --watch
```

In a second terminal, trigger the drift:

```bash
kubectl scale deployment hello-world --replicas=5
```

Switch back to the first terminal -- 3 new pods appear, then get
terminated and removed once ArgoCD notices the live state doesn't
match Git. This runs through Kubernetes' watch API once a resource is
already under ArgoCD's management, not the ~3-minute interval that
governs polling Git for new commits -- self-heal typically kicks in
within seconds. `Ctrl+C` once it settles back to 2.

The ArgoCD UI, open at the same time on the Application's resource
tree, makes this even more visible -- watch it flip `OutOfSync` back
to `Synced` and the pod count shrink in real time. That's ArgoCD's own
view of noticing and fixing it, not just the downstream effect.

## Demo sequence

The whole thing runs in about two minutes once it's set up:

1. `./setup.sh <repo-url>` (or skip, if the cluster's already running --
   `kind get clusters` to check)
2. `localhost:30080` -- what's running, what's in Git
3. Edit the ConfigMap, push, refresh the page
4. Start `kubectl get pods -l app=hello-world --watch` in one pane,
   the ArgoCD UI open on the Application's resource tree in another,
   then `kubectl scale --replicas=5` in a third -- watch both views
   catch and correct it live, rather than checking a before/after

Worth running through once before showing it live, the same as any
demo. Confirm the steps above actually work on the machine and repo
being used, not just in theory.

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
- **Terminal vs. UI show different layers of the same event.**
  `kubectl get pods --watch` is a direct watch against the API server
  -- every phase the kubelet reports (`Pending`, `ContainerCreating`,
  `Terminating`, even a brief `Error` if self-heal interrupts
  something mid-startup), with minimal latency. The ArgoCD UI's
  resource tree summarizes at the Application level instead -- in
  sync or not, healthy or not -- not every container-runtime
  transition underneath. Running both side by side during the
  drift/self-heal sequence is more convincing than either alone,
  precisely because neither one is "sanitized" -- they're just
  genuinely different views of the same real event.

## Tearing down

```bash
./teardown.sh
```

Deletes the kind cluster entirely. Nothing else on the machine is
touched -- everything lived inside that one cluster.
