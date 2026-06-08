import Toybox.Graphics;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

class DrizzleView extends WatchUi.View {

    private const CACHE_MS = 300000;
    private const ZOOM_FACTOR = 2;
    private const FRAME_DELAY_SHORT_MS = 500;
    private const FRAME_DELAY_LONG_MS = 2000;

    private var _image = null;
    private var _cache = {};
    private var _animationFrames = [null, null, null, null, null, null];
    private var _animationTimer = null;
    private var _animationMode = false;
    private var _animationLoading = false;
    private var _frameIndex = 0;
    private var _framesLoaded = 0;
    private var _selectedKey = "USA";
    private var _stateCode = null;
    private var _selectionLabel = "USA";
    private var _status = "Menu refreshes. Select toggles zoom.";
    private var _isLoading = false;
    private var _pendingKey = null;
    private var _zoomed = false;
    private var _radarX = 0;
    private var _radarY = 42;
    private var _fitRadarWidth = 400;
    private var _fitRadarHeight = 300;
    private var _radarWidth = 400;
    private var _radarHeight = 300;
    private var _panX = 0;
    private var _panY = 0;
    private var _dragStartX = 0;
    private var _dragStartY = 0;
    private var _dragStartPanX = 0;
    private var _dragStartPanY = 0;

    function initialize() {
        View.initialize();
    }

    function onShow() {
        setActionMenuIndicator({ :enabled => true });
        load(false);
    }

    function onHide() as Void {
        stopAnimationTimer();
    }

    function onUpdate(dc) {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var isSquareOrRound = height <= (width + 8);
        _fitRadarWidth = isSquareOrRound ? (width * 86 / 100) : width;
        _fitRadarHeight = _fitRadarWidth * 3 / 4;

        _radarWidth = _zoomed ? (_fitRadarWidth * ZOOM_FACTOR) : _fitRadarWidth;
        _radarHeight = _zoomed ? (_fitRadarHeight * ZOOM_FACTOR) : _fitRadarHeight;

        _radarX = (width - _radarWidth) / 2;
        _radarY = 58;
        var imageY = _zoomed ? (_radarY - ((_radarHeight - _fitRadarHeight) / 2)) : _radarY;
        var viewportX = (width - _fitRadarWidth) / 2;
        var footerY = _radarY + _fitRadarHeight + 12;

        clampPan();

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        dc.setColor(0x0d1117, 0x0d1117);
        dc.fillRectangle(viewportX, _radarY, _fitRadarWidth, _fitRadarHeight);

        if (_image != null) {
            dc.setClip(viewportX, _radarY, _fitRadarWidth, _fitRadarHeight);
            if (_zoomed) {
                dc.drawScaledBitmap(_radarX + _panX, imageY + _panY, _radarWidth, _radarHeight, _image);
            } else {
                dc.drawScaledBitmap(viewportX, _radarY, _fitRadarWidth, _fitRadarHeight, _image);
            }
            dc.clearClip();
        } else {
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(width / 2, _radarY + (_fitRadarHeight / 2) - 10, Graphics.FONT_XTINY, "Radar will appear here", Graphics.TEXT_JUSTIFY_CENTER);
        }

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawText(width / 2, 16, Graphics.FONT_TINY, "Drizzle - " + _selectionLabel, Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(width / 2, footerY, Graphics.FONT_XTINY, _status, Graphics.TEXT_JUSTIFY_CENTER);
    }

    function selectUSA() {
        _selectedKey = "USA";
        _stateCode = null;
        _selectionLabel = DrizzleData.displayName("USA");
        _zoomed = false;
        resetPan();
        load(false);
    }

    function selectRegion(key) {
        _selectedKey = key;
        _stateCode = null;
        _selectionLabel = DrizzleData.displayName(key);
        _zoomed = false;
        resetPan();
        load(false);
    }

    function selectState(code) {
        _stateCode = code;
        _selectedKey = DrizzleData.resolvedKeyForState(code);
        _selectionLabel = DrizzleData.resolvedLabelForState(code);
        _zoomed = false;
        resetPan();
        load(false);
    }

    function load(force) {
        var now = System.getTimer();

        if (!force && _cache.hasKey(_selectedKey)) {
            var cached = _cache[_selectedKey];
            if ((now - cached["time"]) < CACHE_MS) {
                _animationMode = cached.hasKey("frames");
                if (_animationMode) {
                    _animationFrames = cached["frames"];
                    _frameIndex = 0;
                    _image = _animationFrames[_frameIndex];
                    _status = _zoomed ? "Zoom: animated radar" : "Animated radar";
                    startAnimationTimer();
                } else {
                    _image = cached["image"];
                    _status = _zoomed ? "Zoomed cached radar" : "Fresh cached radar";
                    stopAnimationTimer();
                    requestAnimationFrames(_selectedKey, false);
                }
                _isLoading = false;
                WatchUi.requestUpdate();
                return;
            }
        }

        requestKey(_selectedKey, false);
    }

    function requestKey(key, isFallback) {
        _animationMode = false;
        _animationLoading = false;
        stopAnimationTimer();
        _isLoading = true;
        _pendingKey = key;
        _status = "Loading radar";
        WatchUi.requestUpdate();

        var request = new RadarRequest(self, key, isFallback);
        request.start(DrizzleData.resolveRadarUrl(key), 640, 480);
    }

    function requestAnimationFrames(key, isFallback) {
        if (!DrizzleData.useFrameConverter()) {
            return;
        }

        _animationMode = false;
        _animationLoading = true;
        stopAnimationTimer();
        _animationFrames = [null, null, null, null, null, null];
        _frameIndex = 0;
        _framesLoaded = 0;
        _pendingKey = key;

        requestAnimationFrame(key, isFallback, 0);
    }

    function requestAnimationFrame(key, isFallback, frameIndex) {
        var request = new RadarFrameRequest(self, key, isFallback, frameIndex);
        request.start(DrizzleData.resolveFrameUrl(key, frameIndex), 640, 480);
    }

    function onRadarResponse(key, isFallback, responseCode, data) {
        if (key != _pendingKey) {
            return;
        }

        if (responseCode == 200 && data != null) {
            _image = data;
            _animationMode = false;
            stopAnimationTimer();
            _cache[key] = {
                "image" => data,
                "time" => System.getTimer()
            };
            _isLoading = false;
            if (isFallback) {
                _status = "Showing " + DrizzleData.displayName(key);
            } else {
                _status = _zoomed ? "Zoomed radar frame" : "Radar frame";
            }
            WatchUi.requestUpdate();
            requestAnimationFrames(key, isFallback);
            return;
        }

        if (_stateCode != null && !isFallback) {
            var fallback = DrizzleData.fallbackRegionForState(_stateCode);
            requestKey(fallback, true);
            return;
        }

        _isLoading = false;
        _status = "Radar unavailable";
        WatchUi.requestUpdate();
    }

    function onRadarFrameResponse(key, isFallback, frameIndex, responseCode, data) {
        if (key != _pendingKey || !_animationLoading) {
            return;
        }

        if (responseCode != 200 || data == null) {
            _animationLoading = false;
            _animationMode = false;
            stopAnimationTimer();
            _status = _zoomed ? "Zoomed radar frame" : "Radar frame";
            WatchUi.requestUpdate();
            return;
        }

        _animationFrames[frameIndex] = data;
        _framesLoaded += 1;

        if (frameIndex + 1 < DrizzleData.ANIMATION_FRAME_COUNT) {
            requestAnimationFrame(key, isFallback, frameIndex + 1);
            return;
        }

        _animationLoading = false;
        _animationMode = true;
        _frameIndex = 0;
        _image = _animationFrames[_frameIndex];
        _cache[key] = {
            "frames" => _animationFrames,
            "time" => System.getTimer()
        };
        _isLoading = false;
        _status = _zoomed ? "Zoom: animated radar" : "Animated radar";
        startAnimationTimer();
        WatchUi.requestUpdate();
    }

    function toggleZoom() {
        if (_image == null || _isLoading) {
            return;
        }

        _zoomed = !_zoomed;
        if (_zoomed) {
            resetPan();
        }
        if (_animationMode) {
            _status = _zoomed ? "Zoom: animated radar" : "Animated radar";
        } else {
            _status = _zoomed ? "Zoom: drag/swipe to pan" : "Radar frame";
        }
        WatchUi.requestUpdate();
    }

    function isZoomed() {
        return _zoomed && _image != null && !_isLoading;
    }

    function beginDrag(x, y) {
        if (!isZoomed()) {
            return false;
        }

        _dragStartX = x;
        _dragStartY = y;
        _dragStartPanX = _panX;
        _dragStartPanY = _panY;
        return true;
    }

    function dragTo(x, y) {
        if (!isZoomed()) {
            return false;
        }

        _panX = _dragStartPanX + (x - _dragStartX);
        _panY = _dragStartPanY + (y - _dragStartY);
        clampPan();
        _status = _animationMode ? "Zoom: animated radar" : "Zoom: drag/swipe to pan";
        WatchUi.requestUpdate();
        return true;
    }

    function endDrag() {
        if (!isZoomed()) {
            return false;
        }

        clampPan();
        WatchUi.requestUpdate();
        return true;
    }

    function panBy(dx, dy) {
        if (!isZoomed()) {
            return false;
        }

        _panX += dx;
        _panY += dy;
        clampPan();
        _status = _animationMode ? "Zoom: animated radar" : "Zoom: drag/swipe to pan";
        WatchUi.requestUpdate();
        return true;
    }

    function resetPan() {
        _panX = 0;
        _panY = 0;
        _dragStartX = 0;
        _dragStartY = 0;
        _dragStartPanX = 0;
        _dragStartPanY = 0;
    }

    function clampPan() {
        var maxX = (_radarWidth - _fitRadarWidth) / 2;
        var maxY = (_radarHeight - _fitRadarHeight) / 2;

        if (maxX < 0) {
            maxX = 0;
        }

        if (maxY < 0) {
            maxY = 0;
        }

        if (_panX > maxX) {
            _panX = maxX;
        } else if (_panX < -maxX) {
            _panX = -maxX;
        }

        if (_panY > maxY) {
            _panY = maxY;
        } else if (_panY < -maxY) {
            _panY = -maxY;
        }
    }

    function startAnimationTimer() as Void {
        if (!_animationMode || _image == null || _isLoading) {
            return;
        }

        stopAnimationTimer();
        _animationTimer = new Timer.Timer();
        _animationTimer.start(method(:advanceAnimationFrame), currentFrameDelay(), false);
    }

    function stopAnimationTimer() as Void {
        if (_animationTimer != null) {
            _animationTimer.stop();
            _animationTimer = null;
        }
    }

    function advanceAnimationFrame() as Void {
        if (!_animationMode || _isLoading) {
            stopAnimationTimer();
            return;
        }

        _frameIndex = (_frameIndex + 1) % DrizzleData.ANIMATION_FRAME_COUNT;
        if (_animationFrames[_frameIndex] != null) {
            _image = _animationFrames[_frameIndex];
            WatchUi.requestUpdate();
        }

        startAnimationTimer();
    }

    function currentFrameDelay() {
        if (_frameIndex == (DrizzleData.ANIMATION_FRAME_COUNT - 1)) {
            return FRAME_DELAY_LONG_MS;
        }

        return FRAME_DELAY_SHORT_MS;
    }
}
