# 0011: New views, modifiers, MCP tools, and window hooks plug in from their own files

- **Status:** Accepted
- **Date:** 2026-11-06

## Context

Layout, rendering, and hit testing each had a closed list: the `switch node.kind` blocks in
`LayoutEngine.swift` and `Rendering.swift`, the `LayoutModifier` enum with the cases of its
switches in `LayoutEngine.swift` and `Rendering+Effects.swift`, the tool list in `AgentTools.swift`,
and the event translation in `WindowHost.swift`. About 25 issues of epic #48 add views and
modifiers at the same time. If each edited those lines, every merge would conflict.

## Decision

- **View kinds.** `NodeExtensions` (`Sources/ParhelionUI/NodeBehavior.swift`) maps a node's `kind`
  to a `NodeBehavior`: its size, how it places its children, how it draws, whether a point hits
  it, and whether it is a presentation. A primitive view registers its kind with
  `NodeExtensions.registerOnce(kind:)` the first time it makes its nodes. The layout engine, the
  renderer, and the host look the kind up before their built-in `switch`, so a registered kind
  needs no `case`. Built-in kinds are untouched, and a registered kind of the same name wins.
- **Modifiers.** `LayoutModifier.custom(CustomModifier)` is one new case. A `CustomModifier` is a
  name and string parameters, so the tree stays plain, `Codable` data and the modifier keeps its
  place in the chain. Its `ModifierBehavior`, registered under the name the first time the
  modifier is applied, can change the size, change the rectangle of what it wraps, draw behind
  or in front, and draw what it wraps through a function, as a clip or a shadow does. That last
  hook is how blur, mask, and rotation draw.
- **Input.** A view registers `NodeInputHandlers` with the evaluator, like a button's action.
  `ViewHost.longPress(at:duration:)` and `ViewHost.drag(from:to:duration:)` pass through hit
  testing to the frontmost node with a handler. A drag with no handler under it moves the
  pointer, as a person would.
- **MCP tools and window hooks.** `AgentToolRegistry` and `WindowHookRegistry`, in
  `ParhelionTooling`, take an `AgentTool` or a `WindowHook` from any file. `AgentTools` lists the
  registered tools after the built-in ones, and `parhelion mcp` answers a call to one by running
  its command or returning its result. `WindowHost` turns each SDL event into a `WindowEvent`,
  which has no SDL types, and asks the hooks first.

## Consequences

- A new view kind, modifier, tool, or hook adds files and no `case` in a shared file. Tests in
  `Tests/ParhelionUITests/Extension*Tests.swift` and the tooling tests show each one.
- A view or modifier registers itself because evaluating it runs the registration. Swift cannot
  list the types of a module, and an MCP tool or a window hook is never evaluated, so something
  must call `AgentToolRegistry.shared.register(_:)` or `WindowHookRegistry.shared.register(_:)`
  once at start. Until a better trigger exists, that is one line per tool or hook in the
  executable's start-up, which is a small edit but not none.
- The registry is a process-wide table behind a lock. Two views that register the same kind
  with different behavior replace each other; kind names are the view's type name, as for
  built-in kinds.
- Behaviors are closures over the layout engine and the renderer, which are internal. They are for
  code inside Parhelion, not for apps.
- A registered kind adds one dictionary lookup per node to layout and drawing. The lookup is
  skipped while nothing is registered.
