import Toybox.Lang;
import Toybox.WatchUi;

class DrizzleDelegate extends WatchUi.BehaviorDelegate {

    private const PAN_STEP = 48;

    private var _view;

    function initialize(view) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onSelect() {
        _view.toggleZoom();
        return true;
    }

    function onTap(clickEvent) {
        _view.toggleZoom();
        return true;
    }

    function onDrag(dragEvent) {
        var coords = dragEvent.getCoordinates();
        var dragType = dragEvent.getType();

        if (dragType == WatchUi.DRAG_TYPE_START) {
            return _view.beginDrag(coords[0], coords[1]);
        }

        if (dragType == WatchUi.DRAG_TYPE_CONTINUE) {
            return _view.dragTo(coords[0], coords[1]);
        }

        if (dragType == WatchUi.DRAG_TYPE_STOP) {
            return _view.endDrag();
        }

        return false;
    }

    function onSwipe(swipeEvent) {
        var direction = swipeEvent.getDirection();

        if (direction == WatchUi.SWIPE_LEFT) {
            return _view.panBy(-PAN_STEP, 0);
        }

        if (direction == WatchUi.SWIPE_RIGHT) {
            return _view.panBy(PAN_STEP, 0);
        }

        if (direction == WatchUi.SWIPE_UP) {
            return _view.panBy(0, -PAN_STEP);
        }

        if (direction == WatchUi.SWIPE_DOWN) {
            return _view.panBy(0, PAN_STEP);
        }

        return false;
    }

    function onKey(keyEvent) {
        var key = keyEvent.getKey();

        if (key == WatchUi.KEY_LEFT) {
            return _view.panBy(-PAN_STEP, 0);
        }

        if (key == WatchUi.KEY_RIGHT) {
            return _view.panBy(PAN_STEP, 0);
        }

        if (key == WatchUi.KEY_UP) {
            return _view.panBy(0, PAN_STEP);
        }

        if (key == WatchUi.KEY_DOWN) {
            return _view.panBy(0, -PAN_STEP);
        }

        return false;
    }

    function onPreviousPage() {
        return _view.panBy(0, PAN_STEP);
    }

    function onNextPage() {
        return _view.panBy(0, -PAN_STEP);
    }

    function onMenu() {
        showRadarMenu();
        return true;
    }

    function onActionMenu() {
        showRadarMenu();
        return true;
    }

    function showRadarMenu() {
        var menu = new WatchUi.Menu2({
            :title => "Radar Level",
            :theme => WatchUi.MENU_THEME_BLUE,
            :dividerType => WatchUi.Menu2.DIVIDER_TYPE_DEFAULT
        });

        menu.addItem(new WatchUi.MenuItem("Refresh", "Reload current radar", "refresh", {}));
        menu.addItem(new WatchUi.MenuItem("USA", "National mosaic", "region:USA", {}));

        for (var i = 1; i < DrizzleData.PRIMARY_KEYS.size(); i += 1) {
            var key = DrizzleData.PRIMARY_KEYS[i];
            menu.addItem(new WatchUi.MenuItem(DrizzleData.displayName(key), "Regional mosaic", "region:" + key, {}));
        }

        for (var j = 0; j < DrizzleData.STATE_KEYS.size(); j += 1) {
            var state = DrizzleData.STATE_KEYS[j];
            menu.addItem(new WatchUi.MenuItem(DrizzleData.displayName(state), "State radar", "state:" + state, {}));
        }

        WatchUi.pushView(menu, new DrizzleMenuDelegate(_view), WatchUi.SLIDE_IMMEDIATE);
    }
}

class DrizzleMenuDelegate extends WatchUi.Menu2InputDelegate {

    private var _view;

    function initialize(view) {
        Menu2InputDelegate.initialize();
        _view = view;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId() as Lang.String;

        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);

        if (id == "refresh") {
            _view.load(true);
            return;
        }

        if (id.find("region:") == 0) {
            var key = id.substring(7, id.length());
            if (key == "USA") {
                _view.selectUSA();
            } else {
                _view.selectRegion(key);
            }
            return;
        }

        if (id.find("state:") == 0) {
            _view.selectState(id.substring(6, id.length()));
        }
    }
}
