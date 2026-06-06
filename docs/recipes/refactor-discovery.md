# Recipe: refactor / problem-discovery flow

Owl has no separate `refactor` workflow by design — the discovery-then-slice
flow you want is `composite_feature` started with the `problem_inventory`
variant of its `brief` step. No new workflow needed.

## Start a refactor/discovery task

```sh
owl task create \
  --workflow composite_feature \
  --variant brief=problem_inventory \
  --title "Refactor: <area>"
```

This gives the flow:

```
brief (problem_inventory) → design → decompose → child feature tasks
  → rollup review → archive → commit_push
```

The `problem_inventory` brief variant collects **Scope**, a numbered list of
concrete **Problems** (with one-line evidence each), a **Priority** split
(addressed now vs deferred), and behaviour-preserving **Acceptance criteria**.
`decompose` then creates one child `feature` task per slice; the parent's
`review` step is the rollup.

## When you want a named entry point or extra steps

If you'd rather type `owl task create --workflow refactor`, or the refactor
flow needs its own steps (risk/impact analysis, mandatory design, ranked
candidates), clone `composite_feature` into a project-owned workflow instead
of duplicating it by hand:

```sh
owl workflow new --from composite_feature --id refactor --register
# then tailor the clone entirely through the CLI:
owl workflow source show refactor                       # inspect the raw body
owl workflow context set refactor brief --variant problem_inventory --body -   # adjust prose
# add/rename steps by editing the body and re-saving:
owl workflow source show refactor | <edit> | owl workflow new --id refactor --body - --force
```

The clone is project-owned (`managed: false`), so `owl upgrade` will not
overwrite it. Only promote to a real preset once it genuinely diverges from
`composite_feature` — otherwise the recipe above is the lower-maintenance path.
