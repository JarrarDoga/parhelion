import ParhelionRender

#if canImport(Foundation)
import Foundation
#endif

// How swipe actions are laid out and drawn. They plug in through the
// extension seam (docs/adr/0011-extension-seam.md): a `SwipeActions` node
// holds a row's action buttons, and a `swipeActions` modifier on the row
// clips its sliding content to its cell.

/// The `SwipeActions` node: the buttons of one edge of a row.
func swipeActionsBehavior() -> NodeBehavior {
    NodeBehavior(
        size: { _, _, proposal, _ in
            CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
        },
        place: { engine, node, rect in SwipeLayout.placeButtons(engine, node, rect) },
        draw: { _, node, drawing, canvas in
            // Each action is a rounded rectangle in its tint: red for a
            // destructive button, gray without one. Labels are white.
            for button in node.children {
                guard let frame = button.frame, frame.width > 0, frame.height > 0 else { continue }
                let style =
                    button.attributes["tint"]
                    ?? (button.attributes["role"] == "destructive" ? "red" : "gray")
                canvas.fill(
                    frame, cornerRadius: SwipeLayout.cornerRadius, style: .continuous,
                    color: drawing.color(style))
            }
            drawing.foreground = "white"
        })
}

/// The modifier that keeps a row's sliding content inside its cell.
func swipeClipBehavior() -> ModifierBehavior {
    ModifierBehavior(
        drawEffect: { _, _, drawing, drawInside, canvas in
            let clip = canvas.beginClip(to: drawing.frame, cornerRadius: 0)
            drawInside(&canvas)
            canvas.endClip(clip)
        })
}
