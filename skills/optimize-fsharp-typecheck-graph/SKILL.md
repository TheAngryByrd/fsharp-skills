---
name: optimize-fsharp-typecheck-graph
description: Optimize an F# project's graph-based type-checking critical path with measured compiler evidence. Use when an F# build spends substantial time in type checking, a `.graph.md` file shows excessive file dependencies, shared namespaces or auto-open modules serialize checking, signature files may unblock parallel work, or a compile-performance refactor needs source- and binary-compatibility validation.
---

# Optimize F# Type-check Graph

Make the compiler's conservative file-dependency graph smaller and shallower.
Do not treat a simpler graph as proof of a faster build.
Prove measurement, dependency structure, and compatibility separately.

## 1. Fix the measurement contract

Record the project, SDK, compiler version, configuration, target framework, and
build command. Record the machine conditions and build state.
Time the compiler phase and each file activity. Also time the complete build.
Define the run count, warm-up policy, and minimum useful improvement.

Use repeated runs and compare medians. Keep the raw reports.
Keep the workload, flags, and cleanup procedure identical for both cases.

Complete this step when another person can reproduce the baseline.
The baseline must identify the dominant compiler activities.

## 2. Capture the current graph

These diagnostic flags depend on the F# compiler version. Check them with the selected SDK before collecting a baseline.
Confirm that the build creates both the graph and timing report. A successful build alone does not prove diagnostic support.

Extend, rather than replace, `OtherFlags` for the project under test:

```xml
<OtherFlags>$(OtherFlags) --test:GraphBasedChecking --test:DumpCheckingGraph --times:report.csv</OtherFlags>
```

Build with the measurement contract. Preserve the generated `.graph.md` file
and timing CSV. Identify:

- the longest dependency chain
- high-fan-out files that gate many successors
- expensive `CheckOneImplFile` activities on that chain
- independent files that the graph unnecessarily serializes

Complete this step when each proposed edit names its target edge or bottleneck.

## 3. Classify conservative edges

Check the untyped source constructs that make the compiler infer a dependency:

- Types exposed directly in a shared namespace can link later files that use
  that namespace.
- A global namespace can link the file to all later files.
- A non-prefixed `[<AutoOpen>]` module can link the file to all later files.
- A large module or file can become a genuine bottleneck for many dependents.
- Explicit `open`, qualified names, inheritance, extensions, and inferred types
  can represent real dependencies.

Treat the graph as a conservative superset.
The compiler can infer a syntactic edge that the program does not require.

## 4. Choose the least disruptive cut

Match one experiment to the measured cause:

- For unnecessary shared-namespace edges, isolate internal declarations when
  the existing API contract permits the change.
- For an expensive high-fan-out implementation, test an `.fsi` file.
  Its smaller signature can unblock dependent files.
- For a global or auto-open declaration, remove false dependencies without
  changing its public lookup behavior.
- For a large real boundary, test a file, module, or project split that matches
  the architecture.

Measure each cut before you combine cuts.
Fewer edges can produce little improvement when other work dominates the build.

## 5. Preserve the existing public contract

Inspect current source imports, CLR names, extension lookup, reflection usage,
and compiled consumers. Preserve the required behavior with the smallest
repository-specific mechanism.

Apply these rules:

- Keep the existing public path when the optimization does not require a
  public move.
- Add no facade or auto-open file unless the existing consumer contract
  requires that behavior.
- Use assembly-level `AutoOpen` only when implicit source lookup must remain
  after a justified namespace or module change.
- Treat assembly-level `AutoOpen` as one conditional compatibility tactic.
  It does not restore CLR full names or binary compatibility.
- A module with only `open` statements does not re-export the opened
  declarations.
- Namespace moves can change the meaning or legality of `private`.
  A change to `internal` broadens accessibility and requires API review.
- Namespace moves can break type aliases, extension targets, reflection names,
  C# callers, and compiled consumers.

Complete this step when each public change is necessary and intentional.
Confirm that the experiment adds no unnecessary compatibility mechanism.

## 6. Prove behavior and compatibility

Validate all applicable layers:

1. Build the exact project and the full solution.
2. Run the repository's tests.
3. Compile a minimal source consumer.
   Use only the documented public imports and computation-expression values.
4. Compare public API/assembly metadata before and after.
5. Run an already-compiled consumer when binary compatibility is required.
6. Check each target framework and relevant conditional-compilation branch.

Do not infer compatibility from repository tests alone.

## 7. Re-measure and decide

Repeat the baseline procedure unchanged. Compare:

- median compiler and complete-build durations
- per-file type-check durations
- critical-path depth and fan-out
- variance
- source, binary, and behavioral compatibility results

Accept the refactor only when the measured gain justifies its API and
maintenance costs. Report a small or noisy gain accurately.
A structural experiment still gives useful evidence when you revert it.

## Report

Return an evidence table with the baseline, candidate, change, run count, and
variance. Link both graphs and the raw timing reports.
State these results separately:

1. Removed false edges
2. Remaining critical path
3. Proven compatibility level
4. Keep, revise, or revert decision
