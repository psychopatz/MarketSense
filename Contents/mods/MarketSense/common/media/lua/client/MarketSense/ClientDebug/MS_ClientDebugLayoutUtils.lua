require "ISUI/ISUIElement"

local LayoutUtils = {}

function LayoutUtils.attachPanelClipping(panel)
    -- Disabled: manually setting stencil rect on ISPanel containers was causing invisibility
    -- in some environments. ISScrollingListBox and ISRichTextPanel handle their own clipping.
end

function LayoutUtils.relayoutWidgetScrollbars(widget)
    if not widget then
        return
    end

    if widget.onResize then
        pcall(function()
            widget:onResize()
        end)
    end

    if widget.vscroll then
        local width = widget.getWidth and widget:getWidth() or widget.width or 0
        local height = widget.getHeight and widget:getHeight() or widget.height or 0
        widget.vscroll:setX(math.max(0, width - 13))
        widget.vscroll:setY(0)
        widget.vscroll:setHeight(height)
        widget.vscroll:bringToTop()
    end
end

return LayoutUtils
