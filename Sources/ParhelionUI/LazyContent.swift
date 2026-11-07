#if canImport(Foundation)
import Foundation
#endif

// Lazy content: how a lazy stack or a list finds the views of its content one
// at a time, without evaluating them all. See docs/adr/0016-lazy-windows.md.
//
// Eager evaluation walks a view and returns all of its nodes. Lazy
// evaluation first *flattens* the content into slots, which is cheap: a
// `ForEach` over 5,000 elements is one segment with a count, an identity for
// each element, and a function that evaluates one element. Only the slots in
// the stack's window are then evaluated.

/// What a slot is in a list or a section.
enum LazySlotRole {
    case row, header, footer
}

/// A run of slots that one view makes: the elements of a `ForEach`, or one
/// view that is not lazy itself.
struct LazySegment {
    var count: Int
    var role = LazySlotRole.row
    /// The identity of the slot at an index in the segment.
    var identity: @MainActor (Int) -> AnyHashable
    /// Evaluates the slot at an index in the segment.
    var make: @MainActor (Int, Evaluator) -> [ViewNode]
}

/// A section found while flattening, in the slots of a stack.
struct LazySectionInfo {
    /// The slot of the section's header, if it has one.
    var header: Int?
    /// The slots of the section's content.
    var content: Range<Int>
    /// The slot of the section's footer, if it has one.
    var footer: Int?

    var start: Int { header ?? content.lowerBound }
    /// One past the section's last slot.
    var end: Int { (footer ?? content.upperBound - 1) + 1 }
}

/// The slots of one stack, section, or list run, in order.
struct LazySlots {
    private(set) var segments: [LazySegment] = []
    private var starts: [Int] = []
    private(set) var count = 0
    var sections: [LazySectionInfo] = []

    mutating func append(_ segment: LazySegment) {
        guard segment.count > 0 else { return }
        starts.append(count)
        segments.append(segment)
        count += segment.count
    }

    /// The segment that holds a slot, and the slot's index in it.
    private func locate(_ slot: Int) -> (segment: LazySegment, index: Int) {
        var low = 0
        var high = starts.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if starts[middle] <= slot { low = middle } else { high = middle - 1 }
        }
        return (segments[low], slot - starts[low])
    }

    @MainActor
    func identity(of slot: Int) -> AnyHashable {
        let (segment, index) = locate(slot)
        return segment.identity(index)
    }

    func role(of slot: Int) -> LazySlotRole {
        locate(slot).segment.role
    }

    @MainActor
    func make(_ slot: Int, in evaluator: Evaluator) -> [ViewNode] {
        let (segment, index) = locate(slot)
        return segment.make(index, evaluator)
    }

    @MainActor
    var identities: [AnyHashable] {
        segments.flatMap { segment in (0..<segment.count).map { segment.identity($0) } }
    }

    /// A segment for a view that is a single slot, evaluated as a whole.
    @MainActor
    static func single(
        _ view: any View, at path: ViewPath, role: LazySlotRole = .row,
        transform: (@MainActor ([ViewNode]) -> [ViewNode])? = nil
    ) -> LazySegment {
        LazySegment(
            count: 1, role: role, identity: { _ in AnyHashable(path.id.rawValue) },
            make: { _, evaluator in
                let nodes = evaluator.evaluate(view, at: path)
                return transform?(nodes) ?? nodes
            })
    }
}

/// How a container uses lazy content.
enum LazyMode {
    /// The content of a lazy stack: a section stacks its header, content,
    /// and footer with the others.
    case stack
    /// The content of a list: a section starts a run of its own.
    case list
    /// The content of a section in a list.
    case listSection
}

/// A run of slots in a list: a section, or the rows between sections.
struct LazyListRun {
    var id: NodeID
    /// The path that the state of the run's views starts with.
    var statePrefix: String
    var isExplicit: Bool
    var slots: LazySlots
}

/// Collects the slots of a container's content.
struct LazySink {
    let mode: LazyMode
    var slots = LazySlots()
    /// In a list, the runs so far, not counting the one being collected.
    var runs: [LazyListRun] = []
    /// The path the container's implicit sections get their names from.
    let ownPath: ViewPath
    private var implicitCount = 0
    private var hasImplicitRun = false

    init(mode: LazyMode, ownPath: ViewPath) {
        self.mode = mode
        self.ownPath = ownPath
    }

    @MainActor
    mutating func append(_ view: any View, evaluator: Evaluator, at path: ViewPath) {
        if let source = view as? any LazyContentSource {
            source.appendLazyContent(to: &self, evaluator: evaluator, at: path)
        } else {
            appendLoose(LazySlots.single(view, at: path))
        }
    }

    /// Adds slots that are not in a section. In a list they join the rows
    /// since the last section.
    mutating func appendLoose(_ segment: LazySegment) {
        slots.append(segment)
        hasImplicitRun = mode == .list
    }

    /// Closes the rows since the last section as a section of their own.
    mutating func closeImplicitRun() {
        guard mode == .list, hasImplicitRun, slots.count > 0 else { return }
        let id = ownPath.appending("Section[\(implicitCount)]").id
        runs.append(
            LazyListRun(
                id: id, statePrefix: ownPath.id.rawValue, isExplicit: false, slots: slots))
        implicitCount += 1
        slots = LazySlots()
        hasImplicitRun = false
    }

    /// Adds a section to a list as a run of its own.
    mutating func appendRun(id: NodeID, slots: LazySlots) {
        closeImplicitRun()
        runs.append(
            LazyListRun(id: id, statePrefix: id.rawValue, isExplicit: true, slots: slots))
    }
}

/// A view that can say what its slots are without evaluating them. Other
/// views are one slot, evaluated whole.
@MainActor
protocol LazyContentSource {
    func appendLazyContent(to sink: inout LazySink, evaluator: Evaluator, at path: ViewPath)
}

extension ForEach: LazyContentSource {
    func appendLazyContent(to sink: inout LazySink, evaluator: Evaluator, at path: ViewPath) {
        let data = data
        let id = id
        let content = content
        func element(_ index: Int) -> Data.Element {
            data[data.index(data.startIndex, offsetBy: index)]
        }
        // A `ForEach` of sections makes its sections' slots, so that a stack
        // can pin their headers and a list can make a run of each. Making
        // the sections' views is cheap: nothing in them is evaluated.
        if Content.self is any LazySectionView.Type {
            for index in 0..<data.count {
                let identity = String(describing: element(index)[keyPath: id])
                sink.append(
                    content(element(index)), evaluator: evaluator,
                    at: path.appending("ForEach[\(identity)]"))
            }
            return
        }
        sink.appendLoose(
            LazySegment(
                count: data.count,
                identity: { AnyHashable(element($0)[keyPath: id]) },
                make: { index, evaluator in
                    let element = element(index)
                    let elementID = element[keyPath: id]
                    let identity = String(describing: elementID)
                    let nodes = evaluator.evaluate(
                        content(element), at: path.appending("ForEach[\(identity)]"))
                    evaluator.environment.tagCollector?.recordImplicit(elementID, for: nodes)
                    return nodes
                }))
    }
}

extension TupleView: LazyContentSource {
    func appendLazyContent(to sink: inout LazySink, evaluator: Evaluator, at path: ViewPath) {
        for (index, element) in elements.enumerated() {
            sink.append(element, evaluator: evaluator, at: path.appending(String(index)))
        }
    }
}

extension _ConditionalContent: LazyContentSource {
    func appendLazyContent(to sink: inout LazySink, evaluator: Evaluator, at path: ViewPath) {
        switch storage {
        case .trueContent(let content):
            sink.append(content, evaluator: evaluator, at: path.appending("if"))
        case .falseContent(let content):
            sink.append(content, evaluator: evaluator, at: path.appending("else"))
        }
    }
}

extension Optional: LazyContentSource where Wrapped: View {
    func appendLazyContent(to sink: inout LazySink, evaluator: Evaluator, at path: ViewPath) {
        if case .some(let content) = self {
            sink.append(content, evaluator: evaluator, at: path.appending("if"))
        }
    }
}

extension Group: LazyContentSource where Content: View {
    func appendLazyContent(to sink: inout LazySink, evaluator: Evaluator, at path: ViewPath) {
        sink.append(content, evaluator: evaluator, at: path)
    }
}

extension EmptyView: LazyContentSource {
    func appendLazyContent(to sink: inout LazySink, evaluator: Evaluator, at path: ViewPath) {}
}

/// A view that is a ``Section``.
protocol LazySectionView {}

extension Section: LazySectionView {}

extension Section: LazyContentSource {
    func appendLazyContent(to sink: inout LazySink, evaluator: Evaluator, at path: ViewPath) {
        let ownPath = path.appending("Section")
        switch sink.mode {
        case .stack:
            // In a lazy stack, a section's header, content, and footer are
            // stacked with the other views, as in SwiftUI.
            var info = LazySectionInfo(header: nil, content: 0..<0, footer: nil)
            if Parent.self != EmptyView.self {
                info.header = sink.slots.count
                sink.slots.append(LazySlots.single(header, at: ownPath.appending("header")))
            }
            let first = sink.slots.count
            sink.append(content, evaluator: evaluator, at: ownPath)
            info.content = first..<sink.slots.count
            if Footer.self != EmptyView.self {
                info.footer = sink.slots.count
                sink.slots.append(LazySlots.single(footer, at: ownPath.appending("footer")))
            }
            sink.slots.sections.append(info)

        case .listSection:
            // A section inside a section is not supported lazily: it is one
            // slot, and the list falls back to evaluating everything.
            sink.appendLoose(LazySlots.single(self, at: path))

        case .list:
            // A section in a list is a run of its own, with its header and
            // footer as the first and last slots.
            var inner = LazySink(mode: .listSection, ownPath: ownPath)
            let headerPath = ownPath.appending("header")
            let footerPath = ownPath.appending("footer")
            let hasHeader = Parent.self != EmptyView.self
            let hasFooter = Footer.self != EmptyView.self
            let header = header
            let footer = footer
            // In a list, headers and footers have their own fonts, which a
            // font set inside them overrides.
            if hasHeader {
                inner.slots.append(
                    LazySegment(
                        count: 1, role: .header, identity: { _ in AnyHashable("header") },
                        make: { _, evaluator in
                            let nodes = evaluator.withEnvironment({
                                $0.font = LayoutDefaults.listHeaderFont
                            }) { evaluator.evaluate(header, at: headerPath) }
                            return nodes.isEmpty
                                ? []
                                : [
                                    ViewNode(
                                        id: headerPath.id, kind: "SectionHeader", children: nodes)
                                ]
                        }))
            }
            inner.append(content, evaluator: evaluator, at: ownPath)
            if hasFooter {
                inner.slots.append(
                    LazySegment(
                        count: 1, role: .footer, identity: { _ in AnyHashable("footer") },
                        make: { _, evaluator in
                            let nodes = evaluator.withEnvironment({
                                $0.font = LayoutDefaults.listFooterFont
                            }) { evaluator.evaluate(footer, at: footerPath) }
                            return nodes.isEmpty
                                ? []
                                : [
                                    ViewNode(
                                        id: footerPath.id, kind: "SectionFooter", children: nodes)
                                ]
                        }))
            }
            sink.appendRun(id: ownPath.id, slots: inner.slots)
        }
    }
}
