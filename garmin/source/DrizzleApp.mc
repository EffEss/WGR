import Toybox.Application;
import Toybox.WatchUi;

class DrizzleApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() {
        var view = new DrizzleView();
        return [ view, new DrizzleDelegate(view) ];
    }
}
