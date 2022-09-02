# ``AsyncSwiftGit/Repository``

## Topics

### Creating or opening a Repository

- ``init(createAt:bare:)``
- ``init(openAt:)``
- ``clone(from:to:credentials:)``
- ``cloneProgress(from:to:credentials:)``

### Remotes

- ``addRemote(_:url:)``
- ``deleteRemote(_:)``
- ``remoteURL(for:)``

### Branches

- ``createBranch(named:commitOID:force:)``
- ``createBranch(named:target:force:setTargetAsUpstream:)``
- ``deleteBranch(named:)``
- ``branches(type:)``
- ``remoteName(branchName:)``
- ``branchExists(named:)``
- ``upstreamName(of:)``

### References

- ``lookupReference(name:)``
- ``lookupReferenceID(referenceLongName:)``

### Loading data

- ``data(for:)``
- ``addData(_:path:)``
