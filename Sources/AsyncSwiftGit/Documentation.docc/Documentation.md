# ``AsyncSwiftGit``

`AsyncSwiftGit` is an _experimental_ Swift wrapper around the C-language APIs provided by `Clibgit2`. 

## Overview

`AsyncSwiftGit` gets its name from using some of the new concurrency features in Swift, such as using `AsyncThrowingStream` to report progress on long-running operations.

## Topics

### Working with Git repositories

- ``Repository``

### Repository objects

- ``Reference``
- ``Commit``
- ``Tree``
