# Owl Backend Contracts

> Audience: agents and humans implementing a new backend (SQLite, HTTP, …) for an existing Owl domain (Storage, Tasks, Workflows, Artifacts, Config, Publish, Validation).
>
> Source of truth: the `RSpec.shared_examples` block named in each section. Prose here explains intent; the test file is the executable contract.

## Why a contract test

Owl is built on the Backend triplet pattern: `<Domain>::Api` (public surface) → `<Domain>::Backend` (interface module) → `<Domain>::Backends::Filesystem` (current v1 implementation). Future backends (SQLite for embedded container distribution, HTTP for remote-control deployments) are expected to plug into the same interface without API consumers noticing.

Without a formal contract test, an implementation can silently violate the interface in three ways that the existing per-backend specs miss:

- **Type leakage** — returning a `Pathname` from `write` makes filesystem semantics part of the API. A SQLite backend has no Pathname for a row.
- **Exception leakage** — raising `Errno::ENOENT` or `IOError` instead of returning `Result.err(code: :file_not_found)`.
- **Code-name drift** — using `:not_found` or `:missing_role` instead of the documented `:file_not_found` / `:unknown_role`.

The shared-examples block locks the domain-independent half of each backend method's surface. Backend-specific behavior (Pathname returns from Filesystem, SQL transaction semantics from SQLite) stays in per-backend specs.

## Contract surface — Storage

File: `spec/owl/storage/backends/shared/backend_contract.rb`.
Examples name: `RSpec.shared_examples 'Owl storage backend contract'`.

Host group must provide:

- `let(:project_root)` — `Pathname` to a writable project root. The contract creates `.owl/` or nested paths inline when an example needs them.
- `let(:backend)` — backend instance bound to `project_root` (`described_class.new(root: project_root)` for Filesystem).

Inclusion pattern (see `spec/owl/storage/backends/filesystem_spec.rb`):

```ruby
describe 'satisfies the Storage backend contract' do
  around(:each) do |example|
    with_tmp_project { |root| @_project_root = root; example.run }
  end

  let(:project_root) { @_project_root }
  let(:backend) { described_class.new(root: project_root) }

  it_behaves_like 'Owl storage backend contract'
end
```

The contract pins seven invariants:

1. `write(path:, contents:)` followed by `read(path:)` returns the same string bytes.
2. `read(path:)` on a missing key returns `Result.err(code: :file_not_found)` with `details[:path]` set.
3. `exists?(path:)` is `false` before write and `true` after.
4. `mkdir_p(path:)` is idempotent (re-calling on an existing dir is `ok`).
5. `resolve(role:, profile:)` on an unknown role returns `Result.err(code: :unknown_role)` with `details[:available]` listing known roles.
6. `detect_root(start:)` returns `Result.err(code: :project_root_not_found)` for a directory without an `.owl/` marker and `Result.ok(<root>)` when an `.owl/` marker exists upwards.
7. Concurrent writes to the same key are serialized. This example is intentionally `pending` until a backend implements cross-process isolation (SQLite container is the planned trigger).

Things the contract intentionally **does not** check:

- Return type of `write` / `mkdir_p` / `resolve` / `detect_root` — Filesystem returns `Pathname`, but SQLite may return a row id or `nil`. Type is per-backend.
- Path template variable expansion — `{{project.root}}`, `{{env.X}}`, `{{cwd}}` rendering is filesystem-specific (lives in `Internal::PathTemplate`) and is covered in `spec/owl/storage/backends/filesystem_spec.rb` under "filesystem-specific behavior".

## Layer-C exception allowlist

The "no direct File/FileUtils/Dir/Pathname.new in lib/owl/" rule (enforced by `spec/owl/constitution/no_direct_fs_spec.rb`) has five named bootstrap exceptions. Backends exempt from the cross-backend contract because they only ever run in filesystem context:

| # | File | Why it bypasses the backend contract |
|---|---|---|
| 1 | `lib/owl/internal/backend_resolver.rb` (`read_backend_name`) | Reads `.owl/config.yaml` before any backend can be resolved — chicken-and-egg. |
| 2 | `lib/owl/config/backends/filesystem.rb` (`#write_key` via `Internal::Serializer.write_atomic`) and `lib/owl/config/api.rb` (`default_template`) | Config bootstrap: serializer runs before any backend is bound; default template renders without a project context. |
| 3 | `lib/owl/internal/gem_assets.rb` | Gem-shipped read-only assets (bundled JSON schemas, workflow definitions). Path is inside the installed gem, not the user's project. |
| 4 | `lib/owl/cli/internal/user_file_reader.rb` | User-supplied paths outside any project storage. |
| 5 | `lib/owl/init/internal/scaffolder.rb` | Bootstrap writes a `.owl/` skeleton before BackendResolver can route. |

Plus one explicit cross-backend Layer-C exception declared on `Owl::Storage::Backend`:

- `detect_root(start:)` is on the interface but ignores the bound `@root` because it runs before any backend can be selected. Implementations walk their own storage substrate for an `.owl/` marker. The Storage shared examples treat `detect_root` as part of the contract, but every implementation must accept that the bound `@root` is irrelevant for this call.

## Future backend domains

Domains with a public Backend triplet today: Tasks, Workflows, Storage, Artifacts, Config, Publish, Validation. None of them ships with shared_examples yet — Storage is the first. Each domain should grow its own `spec/owl/<domain>/backends/shared/backend_contract.rb` when (and only when) a second backend implementation is on the near-term roadmap (SQLite container is the current driver).

The shared-examples pattern below works for any domain. The host-group `let` values change per domain (e.g. a Tasks contract needs a writable task index, an Artifacts contract needs an artifact-type registry), but the structure stays the same.

## How to add a new backend

1. Implement `Owl::<Domain>::Backends::<Name>` including `Owl::<Domain>::Backend`.
2. Add `spec/owl/<domain>/backends/<name>_spec.rb`.
3. If the domain has a shared contract: include `it_behaves_like 'Owl <domain> backend contract'` inside a host group that provides the required `let` values.
4. Add backend-specific examples for any return-type or invariant that isn't part of the shared contract.
5. Register the backend in `Internal::BackendResolver` (Storage / Workflows / Config / …) so callers can route to it via `.owl/config.yaml`.
6. If the new backend lifts a previously-`pending` shared example to a real assertion (e.g. SQLite making the concurrent-write example real), un-`pending` the shared example and ensure Filesystem still passes — or split the example into a backend-class filter.
