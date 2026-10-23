#if canImport(Foundation)
import Foundation
#endif

/// Pointer input for sliders, which follow a press instead of responding to
/// a tap. The pointer methods in `ViewHost` call these first.
extension ViewHost {
    /// Starts dragging the slider whose track is at a point, and returns the
    /// track's identifier, or returns `nil` if no slider that responds to
    /// input is there.
    func beginSliderDrag(at point: CGPoint) -> NodeID? {
        guard let track = sliderTrack(at: point), let control = sliderControl(track.id) else {
            return nil
        }
        // A press on the knob keeps the knob where it is under the pointer.
        let knob = track.children.first?.frame
        let grabOffset = knob.map { $0.contains(point) ? point.x - $0.midX : 0 } ?? 0
        sliderDragBox(track.id).value = SliderDrag(grabOffset: grabOffset)
        control.onEditingChanged(true)
        return track.id
    }

    /// Moves the knob of the slider being dragged to follow the pointer.
    ///
    /// - Returns: Whether `id` is a slider being dragged.
    func dragSlider(_ id: NodeID, to point: CGPoint) -> Bool {
        guard let drag = sliderDrag(id) else { return false }
        moveSlider(id, knobCenterX: point.x - drag.grabOffset)
        return true
    }

    /// Ends a drag of a slider's knob where the pointer is released. A press
    /// that did not move takes the knob to the point it pressed, unless it
    /// pressed the knob.
    ///
    /// - Returns: Whether `id` is a slider being dragged.
    func endSliderDrag(_ id: NodeID, at point: CGPoint) -> Bool {
        guard let drag = sliderDrag(id) else { return false }
        moveSlider(id, knobCenterX: point.x - drag.grabOffset)
        sliderDragBox(id).value = nil
        sliderControl(id)?.onEditingChanged(false)
        return true
    }

    /// Moves the knob of the slider at a point there, as a tap on its track
    /// does.
    ///
    /// - Returns: Whether a slider that responds to input is at the point.
    func tapSlider(at point: CGPoint) -> Bool {
        guard let track = sliderTrack(at: point), let control = sliderControl(track.id) else {
            return false
        }
        control.onEditingChanged(true)
        moveSlider(track.id, knobCenterX: point.x)
        control.onEditingChanged(false)
        return true
    }

    /// Sets a slider's value so that its knob's center is as close to `x` as
    /// the step allows, then updates the tree.
    private func moveSlider(_ id: NodeID, knobCenterX x: CGFloat) {
        guard let control = sliderControl(id), let track = root.node(withID: id)?.frame else {
            return
        }
        let knobWidth = LayoutDefaults.sliderKnobSize.width
        let travel = track.width - knobWidth
        let fraction = travel > 0 ? Double((x - track.minX - knobWidth / 2) / travel) : 0
        let value = control.value(atFraction: fraction)
        if value != control.value.wrappedValue { control.value.wrappedValue = value }
        update()
    }

    /// The frontmost slider track whose track or knob contains a point, in
    /// the part of the tree that receives input. Content a scroll view clips
    /// does not count.
    private func sliderTrack(at point: CGPoint) -> ViewNode? {
        func search(_ node: ViewNode) -> ViewNode? {
            if node.isScrollContainer, node.frame?.contains(point) != true { return nil }
            for child in node.children.reversed() {
                if let match = search(child) { return match }
            }
            guard node.kind == "SliderTrack", let frame = node.frame else { return nil }
            let knob = node.children.first?.frame ?? frame
            return frame.union(knob).contains(point) ? node : nil
        }
        return search(interactiveRoot)
    }

    private func sliderControl(_ id: NodeID) -> SliderControl? {
        guard root.node(withID: id)?.kind == "SliderTrack" else { return nil }
        return stateBox(forKey: "\(id.rawValue)#slider", initialValue: SliderControl?.none).value
    }

    private func sliderDragBox(_ id: NodeID) -> StateBox<SliderDrag?> {
        stateBox(forKey: "\(id.rawValue)#drag", initialValue: SliderDrag?.none)
    }

    private func sliderDrag(_ id: NodeID) -> SliderDrag? {
        guard root.node(withID: id)?.kind == "SliderTrack" else { return nil }
        return sliderDragBox(id).value
    }
}
