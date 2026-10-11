---
name: fsharp-verify-api
description: Check the real signature of a .NET or F# API before F# code uses it, so the build does not loop on FS0039, FS0001, FS0074, or FS0078. Use when writing F# against a NuGet package, a package version that changed its API, an unfamiliar type, or an .fsx script with #r lines, and before adding a helper that the codebase can already have.
compatibility: The API listing script requires the .NET 10 SDK, PowerShell 7.2 or later, and NuGet access. scripts/global.json selects .NET 10.
---

# Verify an F# API before you use it

Agents write the API that they remember. Packages move, rename, and remove members between versions.
The compiler then reports FS0039 (not defined), and each guess costs one more failed build.
Session evidence ranks FS0039 as the top compiler error. 177 Codex sessions had 4 or more failed builds or test runs.

The fix is to read the signature first. One listing is cheaper than three failed builds.

## Rules

- Find the package version that the project uses. Read the `.fsproj`, `Directory.Packages.props`, or `paket.lock`. Do not assume the latest version.
- Before you call a member that you have not seen in this codebase or in this version, list its signature.
  Use `scripts/show-api.ps1`. It prints the public constructors, methods, properties, and extension methods of a type, with inherited members and F# source names.
  The script exits 0 when the type or member does not exist. A missing member is information, not a failed build.
- Do not probe an API with a build or with speculative `dotnet fsi` code. Each failed probe is a failed build.
- When a type is not defined (FS0039), check the open first: find the namespace of the type in the listing (`TYPE` line) and add that `open`.
- When the compiler reports FS0074, the type comes from an assembly that the project does not reference. Add the package that holds that assembly. Do not add an unrelated package.
- Before you write a helper, search the codebase for one that does the same work. Use `rg` for the result type or for a verb in the name.
- In an `.fsx` script, a relative `#r` path resolves from the script's directory, not from the current directory. FS0078 means the path is wrong.
  Pin each `#r "nuget: Package, Version"` to the project's version. Without a version, FSI loads the latest stable version.

Read [references/LOOKUP.md](references/LOOKUP.md) for each lookup method, the XML docs in the NuGet cache, and the `.fsx` rules.

## Steps

1. List each external type and member that the change uses and that the codebase does not use already.
   Done when each item has a package and a version.
2. For each item, run the listing script and read the real signature:

   ```powershell
   pwsh <skill-root>/scripts/show-api.ps1 -Package FsToolkit.ErrorHandling -Version 5.2.0 -Type FsToolkit.ErrorHandling.Result -Member require
   ```

   Use `-Member ''` to list all members, `-Member ctor` for constructors, and `-Assembly` when the assembly name differs from the package ID.
3. When the signature is not what you remember, find the replacement member in the same listing or in the XML docs. Do not guess a second name.
4. Write the code with the listed signatures, then build once.
5. When the build fails, read the first error only. Later errors are often cascades of the first. Fix it with step 2, not with a guess.

## Verify

Run the proof script from the skill root:

```powershell
pwsh ./scripts/run.ps1
```

The script lists members of two versions of a package that moved its API between versions.
It fails when an expected member is missing or a removed member is present.
