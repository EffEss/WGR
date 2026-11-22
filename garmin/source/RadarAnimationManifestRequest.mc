import Toybox.Communications;
import Toybox.Lang;

class RadarAnimationManifestRequest {

	private var _view;
	private var _key;
	private var _isFallback;

	function initialize(view, key, isFallback) {
		_view = view;
		_key = key;
		_isFallback = isFallback;
	}

	function start(url) {
		var options = {
			:responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
		};

		Communications.makeWebRequest(url, null, options, method(:onResponse));
	}

	function onResponse(responseCode as Lang.Number, data as Lang.Dictionary or Lang.String or Null) as Void {
		_view.onRadarAnimationManifestResponse(_key, _isFallback, responseCode, data);
	}
}
