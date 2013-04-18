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

class Segment
    constructor: (@x0, @y0, @x1, @y1, @diffuse, @reflective, @transmissive) ->

    length: ->
        dx = @x1 - @x0
        dy = @y1 - @y0
        return Math.sqrt(dx*dx + dy*dy)


class Renderer
    # Frontend for running raytracing work on several worker threads, and plotting
    # the results on a Canvas. Uses worker threads for everything.

    kNumBatchWorkers = 2
    kInteractiveRays = 1000
    kMinBatchRays = 5000
    kMaxBatchRays = 200000
    kBatchSizeFactor = 0.1

    callback: () ->

    constructor: (canvasId) ->
        @canvas = document.getElementById(canvasId)
        @canvas.addEventListener('resize', (e) => @resize())

        # We create one 'interactive' worker (where we do accumulation and merges).
        # All other workers are 'batch' workers, which perform bulk background rendering.

        @chooseWorker()
        @interactive = @newWorker()
        @batch = (@newWorker() for i in [1 .. kNumBatchWorkers] by 1)

        # Cookies for keeping track of in-flight changes while rendering
        @latestCookie = 1

        @segments = []
        @exposure = 0.5
        @running = false
        @showSegments = 0

        @resize()

    browserSupported: ->
        # Does this browser have the features we need?

        # Canvas
        return false unless @canvas   
        return false unless @canvas.getContext
        return false unless @canvas.getContext('2d')

        # Web Workers
        return false unless Worker

        # Typed Arrays
        return false unless Uint8ClampedArray
        return false unless Uint32Array

        # Good to go!
        return true

    trimSegments: ->
        # Remove any very small segments from the end of our list

        while @segments.length
            s = @segments.pop()
            if s.length() > 0.1
                @segments.push(s)
                return
        return

    chooseWorker: ->
        # Choose a variant of our worker implementation.
        #
        # We have one in plain JavaScript, which is still faster on most browsers.
        # The newer asm.js version is faster on Chrome, plus we use it if asm.js is
        # supported.

        isChrome = navigator.userAgent.indexOf("Chrome") > 0

        if TestAsmJs() or isChrome
            @workerURI = 'rayworker-asm.js'
        else
            @workerURI = 'rayworker.js'

    newWorker: ->
        w = new Worker(@workerURI)
        w._numPending = 0
        w._cookie = 0
        w.addEventListener 'message', (event) =>
            w = event.target
            msg = event.data

            # The worker just finished something!
            w._numPending--
            w._cookie = msg.cookie

            if msg.job == 'render' or msg.job == 'firstTrace'
                # An image is done rendering. Store it, and notify the UI.

                @raysTraced = msg.raysTraced
                @pixelImage.data.set new Uint8ClampedArray msg.pixels
                @redraw()
                @callback()

            else if msg.job == 'trace'

                # Another thread finished tracing. Send the results to the interactive thread's accumulator,
                # and ask for an async render so we can see the results. Transfer ownership of the temporary
                # array, so we can send it from rendering thread to interactive thread without copying it.

                @interactive.postMessage($.extend(msg, {'job': 'accumulate'}), [msg.counts])
                @asyncRender()

            # Can we begin a firstTrace now?
            if @interactive._numPending == 0 and @interactive._cookie < @latestCookie
                @firstTrace()

            # Any async rendering to do?
            if @interactive._numPending == 0 and @needAsyncRender
                @asyncRender()

            # Can we start any new batch jobs? We only run new batch jobs if the interactive worker is idle.
            # This is lower priority than the above tasks; if we start an async render, for example, no batch jobs
            # will start until that completes.

            if @interactive._numPending == 0
                @startBatchJobs()

        return w

    stop: ->
        @running = false

    start: ->
        @running = true

    resize: ->
        # Set up our canvas
        @width = @canvas.clientWidth
        @height = @canvas.clientHeight
        @canvas.width = @width
        @canvas.height = @height
        @ctx = @canvas.getContext('2d')

        # Create an ImageData that we'll use to transfer pixels back to the canvas
        @pixelImage = @ctx.getImageData(0, 0, @width, @height)

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

    sceneMessage: (args) ->
        return $.extend args,
            width: @width
            height: @height
            lightX: @lightX
            lightY: @lightY
            exposure: @exposure
            segments: @walls.concat(@segments)
            cookie: @latestCookie

    startBatchJobs: ->
        # Start longer-running batch rendering jobs on worker threads that are idle.

        # Scale batches of work so they get longer after the image has settled
        numRays = 0 | Math.min(kMaxBatchRays, Math.max(kMinBatchRays, @raysTraced * kBatchSizeFactor))

        for w in @batch
            continue if w._numPending
            w._numPending++
            w.postMessage @sceneMessage
                job: 'trace'
                numRays: numRays

    clear: ->
        # Clear the histogram, and start rendering an updated version of our scene
        # in a small interactive batch. This will get our 'interactive' worker onto
        # the latest cookie and reset its histogram. This can take some time, so if
        # the worker is already busy we'll defer this until it becomes idle. This is
        # important to prevent interactive udpates from piling up.

        @latestCookie++
        @startTime = new Date

        # Start working immediately?
        if @interactive._numPending == 0
            @firstTrace()

    firstTrace: ->
        # Begin the first trace on a new scene. This should be performed when
        # the interactive worker's cookie is out of date.

        @interactive._numPending++
        @interactive.postMessage @sceneMessage
            job: 'firstTrace'
            numRays: kInteractiveRays

    asyncRender: ->
        # Request an asynchronous rendering update, either immediately or once
        # the interactive thread becomes idle.

        if @interactive._numPending == 0
            @interactive._numPending++
            @interactive.postMessage @sceneMessage
                job: 'render'
            @needAsyncRender = false
        else
            @needAsyncRender = true

    setExposure: (e) ->
        @exposure = e
        @asyncRender()

    toDataURL: (mime) ->
        # Return rendered image data

        @ctx.putImageData(@pixelImage, 0, 0)
        return @canvas.toDataURL(mime)

    redraw: ->
        # Image data, as computed by our interactive worker
        @ctx.putImageData(@pixelImage, 0, 0)

        # Draw lines over each segment in our scene
        if @showSegments
            @ctx.strokeStyle = '#ff8'
            @ctx.lineWidth = 3
            for s in @segments
                @ctx.beginPath()
                @ctx.moveTo(s.x0, s.y0)
                @ctx.lineTo(s.x1, s.y1)
                @ctx.stroke()

    elapsedSeconds: ->
        t = new Date()
        return (t.getTime() - @startTime.getTime()) * 1e-3

    raysPerSecond: ->
        return @raysTraced / @elapsedSeconds()

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

