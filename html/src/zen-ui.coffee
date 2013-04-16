#
#   Zen Photon Garden.
#
#   Copyright (c) 2013 Micah Elizabeth Scott <micah@scanlime.org>
#
#   Permission is hereby granted, free of charge, to any person
#   obtaining a copy of this software and associated documentation
#   files (the "Software"), to deal in the Software without
#   restriction, including without limitation the rights to use,
#   copy, modify, merge, publish, distribute, sublicense, and/or sell
#   copies of the Software, and to permit persons to whom the
#   Software is furnished to do so, subject to the following
#   conditions:
#
#   The above copyright notice and this permission notice shall be
#   included in all copies or substantial portions of the Software.
#
#   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
#   EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
#   OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
#   NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
#   HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
#   WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
#   FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
#   OTHER DEALINGS IN THE SOFTWARE.
#


class UndoTracker
    constructor: (@renderer) ->
        @undoQueue = []
        @redoQueue = []

    checkpoint: ->
        @undoQueue.push(@checkpointData())

    checkpointData: ->
        return @renderer.getState()

    restore: (record) ->
        @renderer.setState(record)

    undo: ->
        if @undoQueue.length
            @redoQueue.push(@checkpointData())
            @restore(@undoQueue.pop())

    redo: ->
        if @redoQueue.length
            @checkpoint()
            @restore(@redoQueue.pop())


class GardenUI
    constructor: (canvasId) ->

        @renderer = new Renderer('histogramImage')
        @undo = new UndoTracker(@renderer)

        # First thing first, check compatibility. If we're good, hide the error message and show the help.
        # If not, bail out now.
        return unless @renderer.browserSupported()
        $('#notsupported').hide()
        $('#help').show()
        $('#leftColumn, #rightColumn').fadeIn(1000)

        # Set up our 'exposure' slider
        do (e = @exposureSlider = new VSlider $('#exposureSlider'), $('#workspace')) =>
            e.setValue(@renderer.exposure)
            e.valueChanged = (v) => @renderer.setExposure(v)
            e.beginChange = () => @undo.checkpoint()
            e.endChange = () => @updateLink()

        @renderer.callback = () =>
            $('#raysTraced').text(@renderer.raysTraced)
            $('#raySpeed').text(@renderer.raysPerSecond()|0)

        $('#histogramImage')
            .mousedown (e) =>
                $('#help').fadeOut(2000)

                @undo.checkpoint()
                [x, y] = @mouseXY(e)

                @renderer.trimSegments()
                @renderer.segments.push(new Segment(x, y, x, y,
                    @material[0].value, @material[1].value, @material[2].value))

                @drawingSegment = true
                @renderer.showSegments++
                @renderer.redraw()

                e.preventDefault()

        $('body')
            .mouseup (e) =>
                return unless @drawingSegment
                @drawingSegment = false
                @renderer.showSegments--
                @renderer.redraw()
                @updateLink()

            .mousemove (e) =>
                return unless @drawingSegment
                [x, y] = @mouseXY(e)
                s = @renderer.segments[@renderer.segments.length - 1]
                s.x1 = x
                s.y1 = y

                # Asynchronously start rendering the new scene
                @renderer.clear()

                # Immediately draw the updated segments
                @renderer.redraw()

                e.preventDefault()

        @material = [
            @initMaterialSlider('#diffuseSlider', 1.0),
            @initMaterialSlider('#reflectiveSlider', 0.0),
            @initMaterialSlider('#transmissiveSlider', 0.0),
        ]

        # Show existing segments when hovering over undo/redo/clear
        $('.show-segments-on-hover')
            .mouseenter (e) =>
                @renderer.showSegments++
                @renderer.redraw()
            .mouseleave (e) =>
                @renderer.showSegments--
                @renderer.redraw()

        $('#clearButton').button()
            .click (e) =>
                return if !@renderer.segments.length
                @undo.checkpoint()
                @renderer.segments = []
                @renderer.clear()
                @updateLink()

        $('#undoButton').button()
            .hotkey('ctrl+z')
            .hotkey('meta+z')
            .click (e) =>
                @undo.undo()
                @exposureSlider.setValue(@renderer.exposure)
                @updateLink()

        $('#redoButton').button()
            .hotkey('ctrl+y')
            .hotkey('meta+shift+z')
            .click (e) =>
                @undo.redo()
                @exposureSlider.setValue(@renderer.exposure)
                @updateLink()

        $('#pngButton').button()
            .click () =>
                document.location.href = @renderer.toDataURL('image/png').replace('image/png', 'image/octet-stream')

        $('#linkButton').button()
            .click () =>
                @updateLink()
                window.prompt("Copy this URL to share your garden.", document.location)

        # Load saved state, if any
        saved = document.location.hash.replace('#', '')
        if saved
            @renderer.setStateBlob(atob(saved))
            @exposureSlider.setValue(@renderer.exposure)
        @renderer.clear()

        # If the scene is empty, let our 'first run' help show through.
        # This fades out when the first segment is drawn.
        if @renderer.segments.length
            $('#help').hide()

    updateLink: ->
        document.location.hash = btoa(@renderer.getStateBlob())

    mouseXY: (e) ->
        o = $(@renderer.canvas).offset()
        return [e.pageX - o.left, e.pageY - o.top]

    initMaterialSlider: (sel, defaultValue) ->
        widget = new HSlider $(sel)
        widget.setValue(defaultValue)

        # If the material properties add up to more than 1, rebalance them.
        widget.valueChanged = (v) =>
            total = 0
            for m in @material
                total += m.value
            return if total <= 1

            # Leave this one as-is, rescale all other material sliders.
            for m in @material
                continue if m == widget
                if v == 1
                    m.setValue(0)
                else
                    m.setValue( m.value * (1 - v) / (total - v) )

        return widget
