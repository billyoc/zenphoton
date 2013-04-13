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
    onClick: () ->

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
                @onClick(e)

        $('body')
            .mouseup (e) =>
                @dragging = false
                @button.uiActive false
                $('body').css cursor: 'auto'

    click: (handler) ->
        @onClick = handler
        return this

    hotkey: (key) ->
        # We only use 'keydown' here... for keys that are also used by the browser UI,
        # keyup and keypress don't work for all keys and platforms we care about.

        $(document).bind 'keydown', key, (e) =>
            @button.uiActive(true)
            setTimeout (() => @button.uiActive(false)), 100
            @onClick(e)

        return this


$.fn.uiActive = (n) ->
    if n
        @addClass('ui-active')
        @removeClass('ui-inactive')
    else
        @removeClass('ui-active')
        @addClass('ui-inactive')
    return this

$.fn.button = () ->
    return new Button this
