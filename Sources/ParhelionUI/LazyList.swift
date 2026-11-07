#if canImport(Foundation)
import Foundation
#endif

// Lazy rows in a `List`. A list with more rows than a screen and its margins
// creates the rows near the screen and records the rest as a count on the
// section that holds them. See docs/adr/0016-lazy-windows.md.

extension List {
    /// The nodes of a list that creates its rows lazily, or `nil` when the
    /// list is short, or when it holds views that make sections of their
    /// own, which the list then evaluates in full.
    func makeLazyNodes(in evaluator: Evaluator, at ownPath: ViewPath) -> [ViewNode]? {
        var sink = LazySink(mode: .list, ownPath: ownPath)
        evaluator.withEnvironment({ $0.isInList = true }) {
            sink.append(content, evaluator: evaluator, at: ownPath)
        }
        sink.closeImplicitRun()
        let total = sink.runs.reduce(0) { $0 + $1.slots.count }
        guard total > LazyDefaults.initialSlots else { return nil }

        // A view in a loose run that makes sections, such as a `ForEach` of
        // `Section`s, is not lazy here. Try the first view of each segment
        // on an evaluator of its own, which leaves no trace.
        let probe = Evaluator(host: evaluator.host)
        probe.environment = evaluator.environment
        probe.environment.isInList = true
        probe.navigation = evaluator.navigation
        for run in sink.runs where !run.isExplicit {
            for segment in run.slots.segments
            where segment.make(0, probe).contains(where: { $0.kind == "Section" }) {
                return nil
            }
        }

        var budget = LazyDefaults.initialSlots
        var sections: [ViewNode] = []
        evaluator.withEnvironment({ $0.isInList = true }) {
            for run in sink.runs {
                let resolution = evaluator.resolveLazySlots(
                    id: run.id, statePrefix: run.statePrefix, run.slots, vertical: true, pinned: [],
                    budget: &budget
                ) { nodes, role in
                    role == .row ? nodes.map { $0.asListRow() } : nodes
                }
                sections.append(
                    ViewNode(
                        id: run.id, kind: "Section", attributes: resolution.attributes,
                        children: resolution.nodes))
            }
        }
        return [
            ViewNode(
                id: ownPath.id, kind: "List", attributes: evaluator.environment.scrollAttributes,
                children: sections)
        ]
    }
}
