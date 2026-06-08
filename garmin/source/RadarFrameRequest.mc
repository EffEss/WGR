import Toybox.Communications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class RadarFrameRequest {

    private var _view;
    private var _key;
    private var _isFallback;
    private var _frameIndex;

    function initialize(view, key, isFallback, frameIndex) {
        _view = view;
        _key = key;
        _isFallback = isFallback;
        _frameIndex = frameIndex;
    }

    function start(url, width, height) {
        var options = {
            :maxWidth => width,
            :maxHeight => height,
            :dithering => Communications.IMAGE_DITHERING_NONE
        };

        Communications.makeImageRequest(url, null, options, method(:onResponse));
    }

    function onResponse(responseCode as Lang.Number, data as WatchUi.BitmapResource or Graphics.BitmapReference or Null) as Void {
        _view.onRadarFrameResponse(_key, _isFallback, _frameIndex, responseCode, data);
    }
}
