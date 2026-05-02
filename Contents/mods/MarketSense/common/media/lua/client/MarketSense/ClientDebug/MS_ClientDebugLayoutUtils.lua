require "ISUI/ISUIElement"

local LayoutUtils = {}

function LayoutUtils.attachPanelClipping(panel)
    if not panel or panel._dtClipAttached then
        return
    end

    local previousPrerender = panel.prerender
    panel.prerender = function(target)
        if previousPrerender then
            previousPrerender(target)
        else
            ISPanel.prerender(target)
        end
        target:setStencilRect(0, 0, target:getWidth(), target:getHeight())
    end

    local stencilClearer = ISUIElement:new(0, 0, 0, 0)
    stencilClearer.prerender = function(element)
        if element and element.parent then
            element.parent:clearStencilRect()
        end
    end
    panel:addChild(stencilClearer)
    panel._dtClipAttached = true
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
