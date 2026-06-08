import Toybox.Communications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class RadarRequest {

    private var _view;
    private var _key;
    private var _isFallback;

    function initialize(view, key, isFallback) {
        _view = view;
        _key = key;
        _isFallback = isFallback;
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
        _view.onRadarResponse(_key, _isFallback, responseCode, data);
    }
}
