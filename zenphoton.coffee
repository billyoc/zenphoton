###
    Zen Photon Garden.

    Copyright (c) 2013 Micah Elizabeth Scott <micah@scanlime.org>

    Permission is hereby granted, free of charge, to any person
    obtaining a copy of this software and associated documentation
    files (the "Software"), to deal in the Software without
    restriction, including without limitation the rights to use,
    copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the
    Software is furnished to do so, subject to the following
    conditions:

    The above copyright notice and this permission notice shall be
    included in all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
    EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
    OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
    NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
    HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
    WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
    FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
    OTHER DEALINGS IN THE SOFTWARE.
###


class Segment
    constructor: (@x0, @y0, @x1, @y1, @diffuse, @reflective, @transmissive) ->
        @calculateProbabilities()
        @calculateNormal()

    setDiffuse: (@diffuse) ->
        @calculateProbabilities()

    setReflective: (reflective) ->
        @calculateProbabilities()

    setTransmissive: (transmissive) ->
        @calculateProbabilities()

    setPoint0: (@x0, @y0) ->
        @calculateNormal()

    setPoint1: (@x1, @y1) ->
        @calculateNormal()

    calculateProbabilities: ->
        @d1 = @diffuse
        @r2 = @d1 + @reflective
        @t3 = @r2 + @transmissive

    calculateNormal: ->
        dx = @x1 - @x0
        dy = @y1 - @y0
        len = Math.sqrt(dx*dx + dy*dy)
        @xn = -dy / len
        @yn = dx / len


class Renderer
    # Frontend for running raytracing work on several worker threads, and plotting
    # the results on a Canvas.

    constructor: (canvasId) ->
        @canvas = document.getElementById(canvasId)
        @canvas.addEventListener('resize', (e) => @resize())

        # Hardcoded threadpool size
        @workerURI = 'rayworker.js'

        # Placeholders for real workers, created in @start()
        @workers = ({'_index': i} for i in [0..1])

        # Cookies for keeping track of in-flight changes while rendering
        @workCookie = 1
        @bufferCookie = 0

        @callback = () -> null
        @segments = []
        @exposure = 0.5

        @running = false
        @resize()

    resize: ->
        # Set up our canvas
        @width = @canvas.clientWidth
        @height = @canvas.clientHeight
        @canvas.width = @width
        @canvas.height = @height
        @ctx = @canvas.getContext('2d')

        # Create an ImageData that we'll use to transfer pixels back to the canvas
        @pixelImage = @ctx.getImageData(0, 0, @width, @height)
        @pixels = new Uint8ClampedArray @pixelImage.data.length

        # Reinitialize the histogram
        @counts = new Uint32Array(@width * @height)
        @clear()

        # Light source
        @lightX = @width / 2
        @lightY = @height / 2

        # Scene walls
        @walls = [
            new Segment(0, 0, @width-1, 0, 0,0,0),
            new Segment(0, 0, 0, @height-1, 0,0,0),
            new Segment(@width-1, @height-1, @width-1, 0, 0,0,0),
            new Segment(@width-1, @height-1, 0, @height-1, 0,0,0),
        ]

    getState: ->
        return [
            @exposure,
            @segments.slice(),
            @lightX,
            @lightY,
        ]

    setState: (record) ->
        [
            @exposure,
            @segments,
            @lightX,
            @lightY,
        ] = record
        @clear()

    getStateBlob: ->
        bytes = []
        formatVersion = 0

        push8 = (v) ->
            bytes.push(String.fromCharCode(v|0))

        push8F = (v) ->
            # Normalize a float from [0,1] to an 8-bit value
            push8(Math.max(0, Math.min(255, (v * 255)|0)))

        push16 = (v) ->
            push8((v|0) >> 8)
            push8((v|0) & 0xFF)

        push8(formatVersion)
        push16(@width)
        push16(@height)
        push16(@lightX)
        push16(@lightY)
        push8F(@exposure)
        push16(@segments.length)

        for s in @segments
            push16(s.x0)
            push16(s.y0)
            push16(s.x1)
            push16(s.y1)
            push8F(s.diffuse)
            push8F(s.reflective)
            push8F(s.transmissive)

        return bytes.join('')

    setStateBlob: (s) ->
        formatVersion = s.charCodeAt(0)
        @setStateBlobV0(s) if formatVersion == 0
        @clear()

    setStateBlobV0: (s) ->
        @width = (s.charCodeAt(1) << 8) | s.charCodeAt(2)
        @height = (s.charCodeAt(3) << 8) | s.charCodeAt(4)
        @lightX = (s.charCodeAt(5) << 8) | s.charCodeAt(6)
        @lightY = (s.charCodeAt(7) << 8) | s.charCodeAt(8)
        @exposure = s.charCodeAt(9) / 255.0

        @segments = []
        numSegments = (s.charCodeAt(10) << 8) | s.charCodeAt(11)

        o = 12
        while numSegments--
            x0 = (s.charCodeAt(0+o) << 8) | s.charCodeAt(1+o)
            y0 = (s.charCodeAt(2+o) << 8) | s.charCodeAt(3+o)
            x1 = (s.charCodeAt(4+o) << 8) | s.charCodeAt(5+o)
            y1 = (s.charCodeAt(6+o) << 8) | s.charCodeAt(7+o)
            diffuse = s.charCodeAt(8+o) / 255.0
            reflective = s.charCodeAt(9+o) / 255.0
            transmissive = s.charCodeAt(10+o) / 255.0

            o += 11
            @segments.push(new Segment(
                x0, y0, x1, y1, diffuse, reflective, transmissive))

    stop: ->
        @running = false

    start: ->
        @running = true
        @workCookie++
        for w in @workers
            @initWorker(w)

    workerMessage: (event) ->
        worker = event.target
        msg = event.data
        n = @width * @height
        d = @counts

        # The work unit we just got back was stemped with a cookie indicating
        # which version of our scene it belonged with. If this is older than
        # the buffer's cookie, we must discard the work. If it's the same, we can
        # merge it with the existing buffer. If it's newer, we need to begin a
        # fresh buffer.

        if msg.cookie > @bufferCookie
            @raysTraced = 0
            for i in [0..n] by 1
                d[i] = 0
            @bufferCookie = msg.cookie

            # Immediately kill any other threads that are working on a job older than this buffer.
            for w in @workers
                if w._latestCookie and w._latestCookie < @bufferCookie
                    @initWorker(w)

        if msg.cookie == @bufferCookie
            s = new Uint32Array(msg.counts)
            for i in [0..n] by 1
                d[i] += s[i]
            @raysTraced += msg.numRays
            @callback()

        @scheduleWork(worker)

    scheduleWork: (worker) ->
        if @workCookie != @bufferCookie
            # Parameters changing; use a minimal batch size
            numRays = 1000
        else
            # Scale batches of work so they get longer after the image has settled
            numRays = 0 | Math.min(199999, Math.max(1000, @raysTraced / 2))

        worker._latestCookie = @workCookie
        worker._numRays = numRays

        worker.postMessage({
            'job': 'trace',
            'width': @width,
            'height': @height,
            'lightX': @lightX,
            'lightY': @lightY,
            'segments': @walls.concat(@segments),
            'numRays': numRays,
            'cookie': @workCookie,
            })

    initWorker: (worker, delay) ->
        # (Re)initialize a worker

        index = worker._index
        worker.terminate() if worker.terminate

        worker = new Worker(@workerURI)
        worker._index = index
        worker._latestCookie = null
        worker._numRays = 0

        @workers[index] = worker
        worker.addEventListener('message', (e) => @workerMessage(e))
        @scheduleWork(worker)

    clear: ->
        # Increment the version cookie on our scene, while we allow
        # older versions to draw anyway. Otherwise, we'll keep preempting
        # ourselves before a single frame is rendered.
        @workCookie++

        @startTime = new Date

        if @running
            # If any threads are running really large batches, reset them now.
            for w in @workers
                if w._numRays >= 10000
                    @initWorker(w)

    elapsedSeconds: ->
        t = new Date()
        return (t.getTime() - @startTime.getTime()) * 1e-3

    raysPerSecond: ->
        return @raysTraced / @elapsedSeconds()

    drawLight: (br) ->
        # Draw the current simulation results to our Canvas

        br = Math.exp(1 + 10 * @exposure) / @raysTraced

        n = @width * @height
        pix = @pixels
        c = @counts
        i = 0
        j = 0

        while j != n
            v = c[j++] * br
            pix[i++] = v
            pix[i++] = v
            pix[i++] = v
            pix[i++] = 0xFF

        @pixelImage.data.set(pix)
        @ctx.putImageData(@pixelImage, 0, 0)

    drawSegments: (style, width) ->
        # Draw lines over each segment in our scene

        @ctx.strokeStyle = style
        @ctx.lineWidth = width

        for s in @segments
            @ctx.beginPath()
            @ctx.moveTo(s.x0, s.y0)
            @ctx.lineTo(s.x1, s.y1)
            @ctx.stroke()


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


$.fn.uiActive = (n) ->
    if n
        @addClass('ui-active')
        @removeClass('ui-inactive')
    else
        @removeClass('ui-active')
        @addClass('ui-inactive')


class VSlider
    # Events
    beginChange: () ->
    endChange: () ->
    valueChanged: (v) ->

    constructor: (@button, @track) ->
        @button
            .mousedown (e) =>
                return unless e.which == 1
                @button.uiActive true
                @dragging = true
                @beginChange()
                @updateDrag(e.pageY)
                e.preventDefault()

        $('body')
            .mousemove (e) =>
                return unless @dragging
                @updateDrag(e.pageY)
                e.preventDefault()

            .mouseup (e) =>
                @dragging = false
                @button.uiActive false
                $('body').css cursor: 'auto'
                @endChange()

    updateDrag: (pageY) ->
        h = @button.innerHeight()
        y = pageY - @button.parent().offset().top - h/2
        value = y / (@track.innerHeight() - h)
        value = 1 - Math.min(1, Math.max(0, value))
        $('body').css cursor: 'pointer'
        @setValue(value)
        @valueChanged(value)

    setValue: (@value) ->
        y = (@track.innerHeight() - @button.innerHeight()) * (1 - @value)
        @button.css top: y


class HSlider
    # Events
    beginChange: () ->
    endChange: () ->
    valueChanged: (v) ->

    constructor: (@button) ->
        @button
            .mousedown (e) =>
                return unless e.which == 1
                @dragging = true
                @beginChange()
                @updateDrag(e.pageX)
                e.preventDefault()

        $('body')
            .mousemove (e) =>
                return unless @dragging
                @updateDrag(e.pageX)
                e.preventDefault()

            .mouseup (e) =>
                @dragging = false
                $('body').css cursor: 'auto'
                @endChange()

    updateDrag: (pageX) ->
        w = @button.innerWidth()
        x = pageX - @button.parent().offset().left
        value = Math.min(1, Math.max(0, x / w))
        $('body').css cursor: 'pointer'
        @setValue(value)
        @valueChanged(value)

    setValue: (@value) ->
        w = @button.innerWidth()
        @button.children('.ui-hslider').width(w * @value)


class Button
    # Events
    click: () ->

    constructor: (@button) ->
        @button
            .mousedown (e) =>
                return unless e.which == 1
                @button.uiActive true
                @dragging = true
                $('body').css cursor: 'pointer'
                e.preventDefault()

            .click (e) =>
                @dragging = false
                @button.uiActive false
                $('body').css cursor: 'auto'
                @click()

        $('body')
            .mouseup (e) =>
                @dragging = false
                @button.uiActive false
                $('body').css cursor: 'auto'


class GardenUI
    constructor: (canvasId) ->
        @renderer = new Renderer('histogramImage')
        @undo = new UndoTracker(@renderer)

        # Load saved state, if any
        saved = document.location.hash.replace('#', '')
        if saved
            @renderer.setStateBlob(atob(saved))

        # If the scene is empty, let our 'first run' help show through.
        # This fades out when the first segment is drawn.
        if @renderer.segments.length
            $('#help').hide()

        # Set up our 'exposure' slider
        @exposureSlider = new VSlider $('#exposureSlider'), $('#workspace')
        @exposureSlider.setValue(@renderer.exposure)

        @exposureSlider.valueChanged = (v) =>
            @renderer.exposure = v
            @redraw()

        @exposureSlider.beginChange = () =>
            @undo.checkpoint()

        @exposureSlider.endChange = () =>
            @updateLink()

        @renderer.callback = () =>
            @redraw()
            $('#raysTraced').text(@renderer.raysTraced)
            $('#raySpeed').text(@renderer.raysPerSecond()|0)

        $('#histogramImage')
            .mousedown (e) =>
                $('#help').fadeOut(2000)

                @undo.checkpoint()
                [x, y] = @mouseXY(e)

                @renderer.segments.push(new Segment(x, y, x, y,
                    @material[0].value, @material[1].value, @material[2].value))

                @renderer.clear()
                @drawingSegment = true
                @redraw()
                e.preventDefault()

        $('body')
            .mouseup (e) =>
                @drawingSegment = false
                @updateLink()

            .mousemove (e) =>
                return unless @drawingSegment
                [x, y] = @mouseXY(e)
                s = @renderer.segments[@renderer.segments.length - 1]
                s.setPoint1(x, y)
                @renderer.clear()
                @redraw()
                e.preventDefault()

        @material = [
            @initMaterialSlider('#diffuseSlider', 1.0),
            @initMaterialSlider('#reflectiveSlider', 0.0),
            @initMaterialSlider('#transmissiveSlider', 0.0),
        ]

        (new Button $('#clearButton')).click = () =>
            return if !@renderer.segments.length
            @undo.checkpoint()
            @renderer.segments = []
            @renderer.clear()
            @updateLink()
            @redraw()

        (new Button $('#undoButton')).click = () =>
            @undo.undo()
            @exposureSlider.setValue(@renderer.exposure)
            @updateLink()
            @redraw()

        (new Button $('#redoButton')).click = () =>
            @undo.redo()
            @exposureSlider.setValue(@renderer.exposure)
            @updateLink()
            @redraw()

        (new Button $('#pngButton')).click = () =>
            @renderer.drawLight()
            document.location.href = @renderer.canvas.toDataURL('image/png').replace('image/png', 'image/octet-stream')

        (new Button $('#linkButton')).click = () =>
            @updateLink()
            window.prompt("Copy this URL to share your garden.", document.location)

    updateLink: ->
        document.location.hash = btoa(@renderer.getStateBlob())

    mouseXY: (e) ->
        o = $(@renderer.canvas).offset()
        return [e.pageX - o.left, e.pageY - o.top]

    redraw: ->
        @renderer.drawLight()
        if @drawingSegment
            @renderer.drawSegments('#ff8', 3)

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


$(document).ready(() ->
    ui = new GardenUI
    ui.renderer.start()
)
