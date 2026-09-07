import Toybox.Lang;
import Toybox.WatchUi;

class GarminBatteryAlertInputDelegate extends WatchUi.InputDelegate {

    private var _view as GarminBatteryAlertView;

    function initialize(view as GarminBatteryAlertView) {
        InputDelegate.initialize();
        _view = view;
    }

    function onTap(clickEvent as WatchUi.ClickEvent) as Boolean {
        _view.queueRelayTest();
        return true;
    }
}
