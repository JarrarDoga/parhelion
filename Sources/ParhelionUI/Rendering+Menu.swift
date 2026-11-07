import ParhelionRender

#if canImport(Foundation)
import Foundation
#endif

// Layout and drawing for `Menu` and `contextMenu`. The kinds register
// themselves through the extension seam (NodeBehavior.swift), the first time a
// menu is presented, so no shared file has a `case` for them.
//
// The tree of an open button menu:
//
//     MenuPopover            a presentation covering the screen; a tap closes it
//     └─ MenuPanel           the glass panel
//        ├─ Button …         an item
//        ├─ MenuSeparator    between sections, or a Divider
//        ├─ Section          SectionHeader, items
//        └─ ControlGroup     a row of Buttons, each an icon above its title
//
// and of an open context menu:
//
//     ContextMenu            a presentation: blurs the screen, closes on a tap
//     ├─ ContextMenuPreview  the lifted view, scaled to 1.03 with a shadow
//     └─ MenuPanel

enum MenuLayout {
    /// How much a long press lifts the view.
    static let liftScale: CGFloat = 1.03
    /// The height of the gap between sections.
    static let separatorHeight: CGFloat = 8
    /// The height of a row of a `ControlGroup`.
    static let groupRowHeight: CGFloat = 64
    /// The inset of an item's text when no item has an icon.
    static let textInset: CGFloat = 16
    /// The inset of an item's text when items have icons in a column.
    static let iconTextInset: CGFloat = 40
    /// The space between the lifted view and its menu.
    static let gap: CGFloat = 10
    /// The corner radius of a lifted view without a preview of its own.
    static let previewCornerRadius: CGFloat = 20
    /// The widest a menu grows for a long title.
    static let maxWidth: CGFloat = 320
    /// The blur behind a context menu.
    static let blurRadius: Double = 24

    /// Registers the kinds of menus with the layout engine and the renderer.
    static func registerBehaviors() {
        NodeExtensions.registerOnce(kind: "MenuPopover") {
            NodeBehavior(
                isPresentation: true,
                placePresentation: { engine, node, below in
                    engine.placeMenuPopover(node, over: below)
                }
            )
        }
        NodeExtensions.registerOnce(kind: "ContextMenu") {
            NodeBehavior(
                draw: { renderer, node, drawing, canvas in
                    renderer.drawContextMenuBackdrop(drawing: drawing, into: &canvas)
                },
                isPresentation: true,
                placePresentation: { engine, node, below in
                    engine.placeContextMenu(node, over: below)
                }
            )
        }
        NodeExtensions.registerOnce(kind: "ContextMenuPreview") {
            NodeBehavior(draw: { renderer, node, drawing, canvas in
                renderer.drawContextMenuCard(node, drawing: drawing, into: &canvas)
            })
        }
        NodeExtensions.registerOnce(kind: "MenuPanel") {
            NodeBehavior(draw: { renderer, node, drawing, canvas in
                renderer.drawMenuPanel(node, drawing: &drawing, into: &canvas)
            })
        }
        NodeExtensions.registerOnce(kind: "MenuSeparator") {
            NodeBehavior(draw: { renderer, node, drawing, canvas in
                var color = drawing.palette.separator
                color.alpha = UInt8((Double(color.alpha) * 0.5 * drawing.opacity).rounded())
                canvas.fill(drawing.frame, color: color)
            })
        }
    }
}

// MARK: - Layout

extension LayoutEngine {
    /// Places a button menu next to its button, like a picker's menu: its top
    /// edge level with the button's, and its trailing edge lined up with a
    /// button in the trailing half of the screen, inside the safe area.
    func placeMenuPopover(_ node: ViewNode, over below: [ViewNode]) -> ViewNode {
        var node = node
        let screen = CGRect(origin: .zero, size: device.screenSize)
        let safeArea = device.safeArea
        node.frame = screen
        guard let panel = node.children.first else { return node }
        let anchor =
            node.attributes["anchor"].flatMap { id in
                below.lazy.compactMap { $0.node(withID: NodeID(id))?.hitFrame }.first
            } ?? CGRect(x: safeArea.midX, y: safeArea.midY, width: 0, height: 0)

        let margin = LayoutDefaults.menuMargin
        let width = menuPanelWidth(panel)
        let height = menuPanelHeight(panel)
        var x = anchor.midX >= safeArea.midX ? anchor.maxX - width : anchor.minX
        x = min(max(x, safeArea.minX + margin), safeArea.maxX - margin - width)
        var y = anchor.minY
        if y + height > safeArea.maxY - margin {
            y = max(safeArea.maxY - margin - height, safeArea.minY + margin)
        }
        node.children = [placeMenuPanel(panel, at: CGPoint(x: x, y: y))]
        return node
    }

    /// Places a context menu: the lifted view where the view was, or moved
    /// up to make room, and the menu below it, or above it when the menu
    /// does not fit below.
    func placeContextMenu(_ node: ViewNode, over below: [ViewNode]) -> ViewNode {
        var node = node
        let screen = CGRect(origin: .zero, size: device.screenSize)
        let safeArea = device.safeArea
        node.frame = screen
        guard node.children.count == 2 else { return node }
        var preview = node.children[0]
        let panel = node.children[1]
        let source = node.attributes["anchor"].flatMap { id in
            below.lazy.compactMap { $0.node(withID: NodeID(id)) }.first
        }
        let margin = LayoutDefaults.menuMargin
        let isCustom = preview.attributes["custom"] == "true"

        // Where the lifted view rests, before it moves out of the menu's way.
        var card: CGRect
        var content: CGRect
        if isCustom {
            let anchor =
                source?.hitFrame ?? CGRect(x: safeArea.midX, y: safeArea.midY, width: 0, height: 0)
            let stack = Self.stack("ZStack", preview)
            let size = sizeThatFits(
                stack,
                ProposedSize(width: safeArea.width - 2 * margin, height: safeArea.height / 2),
                parentAxis: nil)
            let x = min(
                max(anchor.midX - size.width / 2, safeArea.minX + margin),
                safeArea.maxX - margin - size.width)
            card = CGRect(origin: CGPoint(x: x, y: anchor.minY), size: size)
            content = card
        } else {
            content =
                source?.frame ?? CGRect(x: safeArea.midX, y: safeArea.midY, width: 0, height: 0)
            card = source?.hitFrame ?? content
        }

        // The menu goes below the lifted view, which grows by the lift.
        let menuHeight = menuPanelHeight(panel)
        let width = menuPanelWidth(panel)
        let grow = card.height * (MenuLayout.liftScale - 1) / 2
        let room = menuHeight + MenuLayout.gap + grow
        var dy: CGFloat = 0
        var placeBelow = true
        if card.maxY + room > safeArea.maxY - margin {
            if card.minY - room >= safeArea.minY + margin {
                placeBelow = false
            } else {
                // Neither side has room: move the lifted view up.
                dy = max(
                    safeArea.maxY - margin - room - card.maxY, safeArea.minY + margin - card.minY)
            }
        }
        card = card.offsetBy(dx: 0, dy: dy)
        content = content.offsetBy(dx: 0, dy: dy)

        var x = card.midX >= safeArea.midX ? card.maxX - width : card.minX
        x = min(max(x, safeArea.minX + margin), safeArea.maxX - margin - width)
        let y = placeBelow ? card.maxY + MenuLayout.gap + grow : card.minY - room

        preview.frame = card
        preview.modifierFrames = Array(repeating: card, count: preview.modifiers.count)
        if isCustom {
            preview.children =
                place(Self.stack("ZStack", preview), in: card, parentAxis: nil)
                .children
        } else {
            preview.children = preview.children.map { place($0, in: content, parentAxis: nil) }
        }
        node.children = [preview, placeMenuPanel(panel, at: CGPoint(x: x, y: y))]
        return node
    }

    /// The width of a menu panel: 250 points, wider when a title needs it, up
    /// to 320 points or the width of the safe area less its margins.
    func menuPanelWidth(_ panel: ViewNode) -> CGFloat {
        let hasIcons = panel.children.contains { Self.menuHasIcon($0) }
        let leading = hasIcons ? MenuLayout.iconTextInset : MenuLayout.textInset
        var widest: CGFloat = 0
        func visit(_ node: ViewNode) {
            switch node.kind {
            case "Section":
                node.children.forEach(visit)
            case "Button":
                let content =
                    Self.titleWithIcon(node.children)?.title ?? Self.stack("HStack", node)
                let width = sizeThatFits(content, .unspecified, parentAxis: nil).width
                widest = max(widest, leading + width + MenuLayout.textInset)
            default:
                break
            }
        }
        panel.children.forEach(visit)
        let limit = min(MenuLayout.maxWidth, device.safeArea.width - 2 * LayoutDefaults.menuMargin)
        let natural = widest + 2 * LayoutDefaults.menuPadding
        return min(max(LayoutDefaults.menuWidth, natural), max(limit, LayoutDefaults.menuWidth))
    }

    /// The height of a menu panel with its padding.
    func menuPanelHeight(_ panel: ViewNode) -> CGFloat {
        placeMenuPanel(panel, at: .zero).frame?.height ?? 0
    }

    /// Places a menu's items in a panel whose top-left corner is `origin`.
    /// The panel's frame is the glass; each item's frame is its cell.
    func placeMenuPanel(_ panel: ViewNode, at origin: CGPoint) -> ViewNode {
        var panel = panel
        let padding = LayoutDefaults.menuPadding
        let panelWidth = menuPanelWidth(panel)
        let width = panelWidth - 2 * padding
        let hasIcons = panel.children.contains { Self.menuHasIcon($0) }
        var y = origin.y + padding
        panel.children = panel.children.map { entry in
            let (placed, height) = placeMenuEntry(
                entry, x: origin.x + padding, y: y, width: width, hasIcons: hasIcons)
            y += height
            return placed
        }
        panel.frame = CGRect(
            x: origin.x, y: origin.y, width: panelWidth,
            height: y + padding - origin.y)
        return panel
    }

    /// Whether an entry, or an item in it, has an icon beside its title, so
    /// that the titles line up after a column for the icons.
    private static func menuHasIcon(_ node: ViewNode) -> Bool {
        switch node.kind {
        case "Section": return node.children.contains { menuHasIcon($0) }
        case "Button": return titleWithIcon(node.children) != nil
        default: return false
        }
    }

    /// The icon and title of a label that has both.
    private static func titleWithIcon(_ content: [ViewNode]) -> (icon: ViewNode, title: ViewNode)? {
        guard content.count == 1, content[0].kind == "Label", content[0].children.count == 2,
            content[0].children[0].kind == "Image"
        else { return nil }
        return (content[0].children[0], content[0].children[1])
    }

    private func placeMenuEntry(
        _ entry: ViewNode, x: CGFloat, y: CGFloat, width: CGFloat, hasIcons: Bool
    ) -> (ViewNode, CGFloat) {
        var entry = entry
        switch entry.kind {
        case "MenuSeparator":
            let height = MenuLayout.separatorHeight
            entry.frame = CGRect(x: x, y: y, width: width, height: height)
            return (entry, height)
        case "Section":
            var top = y
            entry.children = entry.children.map { child in
                let (placed, height) = placeMenuEntry(
                    child, x: x, y: top, width: width, hasIcons: hasIcons)
                top += height
                return placed
            }
            entry.frame = CGRect(x: x, y: y, width: width, height: top - y)
            return (entry, top - y)
        case "SectionHeader", "SectionFooter":
            let inset = hasIcons ? MenuLayout.iconTextInset : MenuLayout.textInset
            return placeMenuText(entry, x: x, y: y, width: width, inset: inset)
        case "ControlGroup":
            return placeControlGroup(entry, x: x, y: y, width: width)
        default:
            return placeMenuItem(entry, x: x, y: y, width: width, hasIcons: hasIcons)
        }
    }

    /// Places a section's header or footer: its text, inset like an item's.
    private func placeMenuText(
        _ node: ViewNode, x: CGFloat, y: CGFloat, width: CGFloat, inset: CGFloat
    ) -> (ViewNode, CGFloat) {
        var node = node
        let available = max(width - inset - MenuLayout.textInset, 0)
        let stack = Self.stack("HStack", node)
        let size = sizeThatFits(stack, ProposedSize(width: available, height: nil), parentAxis: nil)
        let height = size.height + 14
        node.frame = CGRect(x: x, y: y, width: width, height: height)
        node.children =
            place(
                stack, in: CGRect(x: x + inset, y: y + 10, width: size.width, height: size.height),
                parentAxis: nil
            ).children
        return (node, height)
    }

    /// Places an item: a cell with its label inset from the leading edge.
    /// A label with an icon puts the icon in the leading column and the
    /// title after it.
    private func placeMenuItem(
        _ item: ViewNode, x: CGFloat, y: CGFloat, width: CGFloat, hasIcons: Bool
    ) -> (ViewNode, CGFloat) {
        var item = item
        let insets = LayoutDefaults.menuItemInsets
        let leading = hasIcons ? MenuLayout.iconTextInset : MenuLayout.textInset
        let available = max(width - leading - MenuLayout.textInset, 0)
        let content = item.kind == "Button" ? item.children : [item]
        if item.kind == "Button", let (icon, title) = Self.titleWithIcon(content) {
            let titleSize = sizeThatFits(
                title, ProposedSize(width: available, height: nil), parentAxis: nil)
            let iconSize = sizeThatFits(icon, .unspecified, parentAxis: nil)
            let height = max(titleSize.height + insets.vertical, LayoutDefaults.menuItemHeight)
            let midY = y + height / 2
            var label = content[0]
            label.frame = CGRect(
                x: x + MenuLayout.textInset, y: y, width: width - 2 * MenuLayout.textInset,
                height: height)
            label.children = [
                place(
                    icon,
                    in: CGRect(
                        x: x + MenuLayout.textInset, y: midY - iconSize.height / 2,
                        width: iconSize.width, height: iconSize.height), parentAxis: nil),
                place(
                    title,
                    in: CGRect(
                        x: x + leading, y: midY - titleSize.height / 2, width: titleSize.width,
                        height: titleSize.height), parentAxis: nil),
            ]
            item.frame = CGRect(x: x, y: y, width: width, height: height)
            item.children = [label]
            return (item, height)
        }

        let stack = Self.stack(
            "HStack",
            item.kind == "Button" ? item : ViewNode(id: item.id, kind: "HStack", children: [item]))
        let size = sizeThatFits(stack, ProposedSize(width: available, height: nil), parentAxis: nil)
        let height = max(size.height + insets.vertical, LayoutDefaults.menuItemHeight)
        let placed = place(
            stack,
            in: CGRect(
                x: x + leading, y: y + (height - size.height) / 2, width: size.width,
                height: size.height), parentAxis: nil)
        if item.kind == "Button" {
            item.frame = CGRect(x: x, y: y, width: width, height: height)
            item.children = placed.children
        } else {
            item = placed.children.first ?? item
        }
        return (item, height)
    }

    /// Places a control group: equal columns, each with its icon above its
    /// title.
    private func placeControlGroup(
        _ group: ViewNode, x: CGFloat, y: CGFloat, width: CGFloat
    ) -> (ViewNode, CGFloat) {
        var group = group
        let height = MenuLayout.groupRowHeight
        let columnWidth = group.children.isEmpty ? width : width / CGFloat(group.children.count)
        group.frame = CGRect(x: x, y: y, width: width, height: height)
        group.children = group.children.enumerated().map { index, button in
            var button = button
            let column = CGRect(
                x: x + columnWidth * CGFloat(index), y: y, width: columnWidth, height: height)
            button.frame = column
            let inner = column.insetBy(dx: 4, dy: 0)
            let content = button.kind == "Button" ? button.children : [button]
            var parts = content
            if let (icon, title) = Self.titleWithIcon(content) {
                parts = [icon, title]
            }
            let proposal = ProposedSize(width: inner.width, height: nil)
            let sizes = parts.map { sizeThatFits($0, proposal, parentAxis: nil) }
            let spacing: CGFloat = 4
            let total =
                sizes.map(\.height).reduce(0, +) + spacing * CGFloat(max(parts.count - 1, 0))
            var top = column.midY - total / 2
            var placed: [ViewNode] = []
            for (part, size) in zip(parts, sizes) {
                placed.append(
                    place(
                        part,
                        in: CGRect(
                            x: column.midX - size.width / 2, y: top, width: size.width,
                            height: size.height), parentAxis: nil))
                top += size.height + spacing
            }
            if content.count == 1, content[0].kind == "Label", parts.count == 2 {
                var label = content[0]
                label.frame = inner
                label.children = placed
                button.children = [label]
            } else if button.kind == "Button" {
                button.children = placed
            }
            return button
        }
        return (group, height)
    }
}

// MARK: - Drawing

extension TreeRenderer {
    /// Blurs the screen behind a context menu and dims it a little.
    func drawContextMenuBackdrop(drawing: NodeDrawing, into canvas: inout Canvas) {
        canvas.blur(drawing.frame, radius: MenuLayout.blurRadius, saturation: 1.2)
        var dim = RGBA(red: 0, green: 0, blue: 0, alpha: drawing.scheme == .dark ? 77 : 26)
        dim.alpha = UInt8((Double(dim.alpha) * drawing.opacity).rounded())
        canvas.fill(drawing.frame, color: dim)
    }

    /// Draws the card a lifted view rests on: the row's background.
    func drawContextMenuCard(_ node: ViewNode, drawing: NodeDrawing, into canvas: inout Canvas) {
        var color =
            node.attributes["background"] == "groupedRowBackground"
            ? drawing.palette.groupedRowBackground : drawing.palette.background
        color.alpha = UInt8((Double(color.alpha) * drawing.opacity).rounded())
        canvas.fill(
            drawing.frame, cornerRadius: MenuLayout.previewCornerRadius, style: .continuous,
            color: color)
    }

    /// Draws a menu's glass, the highlight of a pressed item, and the lines
    /// between the columns of a control group.
    func drawMenuPanel(_ node: ViewNode, drawing: inout NodeDrawing, into canvas: inout Canvas) {
        let palette = drawing.palette
        canvas.drawGlass(
            drawing.frame, cornerRadius: LayoutDefaults.menuCornerRadius, style: .continuous,
            material: palette.menuGlass, opacity: drawing.opacity)
        drawing.foreground = drawing.foreground ?? "primary"

        if let pressed = pressedNodeID,
            let cell = node.node(withID: pressed)?.frame,
            node.node(withID: pressed)?.kind == "Button"
        {
            var color = palette.menuHighlight
            color.alpha = UInt8((Double(color.alpha) * drawing.opacity).rounded())
            let outer = canvas.blendMode
            canvas.blendMode = palette.menuHighlightBlendMode
            canvas.fill(
                cell, cornerRadius: LayoutDefaults.menuHighlightCornerRadius, style: .continuous,
                color: color)
            canvas.blendMode = outer
        }
        var line = palette.separator
        line.alpha = UInt8((Double(line.alpha) * drawing.opacity).rounded())
        for group in node.allNodes where group.kind == "ControlGroup" {
            for column in group.children.dropFirst() {
                guard let frame = column.frame else { continue }
                canvas.fill(
                    CGRect(
                        x: frame.minX - 0.25, y: frame.minY + 12, width: 0.5,
                        height: frame.height - 24),
                    color: line)
            }
        }
    }
}
