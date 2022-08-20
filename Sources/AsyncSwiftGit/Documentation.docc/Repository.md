# ``AsyncSwiftGit/Repository``

## Topics

### Creating or opening a Repository

- ``init(createAt:bare:)``
- ``init(openAt:)``
- ``clone(from:to:credentials:)``
- ``cloneProgress(from:to:credentials:)``

### Working with branches

- ``createBranch(named:commitOID:force:)``
- ``createBranch(named:target:force:setTargetAsUpstream:)``
- ``branches(type:)``
- ``remoteName(branchName:)``
- ``branchExists(named:)``
- ``upstreamName(of:)``
