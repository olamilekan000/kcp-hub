# Contributing to kcp hub

## Picking up work

Work is tracked in [issues](https://github.com/olamilekan000/kcp-hub/issues),
grouped under the
[v0.1 roadmap](https://github.com/olamilekan000/kcp-hub/issues/13) in the
order it should be done. Comment on an issue before starting so nobody
duplicates it.

## Making a change

1. Branch from `main`.
2. Run `make lint` before pushing. CI runs the same checks, plus a check that
   links in markdown files still resolve and that every commit is signed off.
3. Open a pull request that says `Closes #<issue>` in its description.

`make help` lists everything the Makefile can do.

## Certificate of Origin

By contributing to this project you agree to the Developer Certificate of
Origin (DCO). It is a simple statement that you, as a contributor, have the
legal right to make the contribution. See the [DCO](DCO) file for details.

The DCO requires a human to certify the contribution. AI agents cannot
legally provide this certification.

To accept it, sign off every commit with `-s`:

```sh
git commit -s -m "my commit message"
```

which adds a line like this to the commit:

```text
Signed-off-by: Your Name <mail@example.com>
```

A check on every pull request rejects commits without it. To fix commits you
already made, run `git rebase --signoff main` and force-push.

## Use of AI coding assistants

You are welcome to use AI tools, but you remain fully responsible for every
contribution you submit, and must review and understand all of it before
opening a pull request.

AI tools are not authors. Contributions that attribute authorship or sign-off
to an AI tool are not accepted, for example `Signed-off-by: <AI tool>`,
`Co-authored-by: <AI tool>` or `Generated with <AI tool>`. There is no need to
add `Assisted-by` markers either.

## Repository layout

| Path | What lives there |
|---|---|
| `deploy/` | Manifests and charts that install the platform |
| `hack/` | Scripts used by the Makefile and CI |
| `docs/` | Documentation and diagrams |
