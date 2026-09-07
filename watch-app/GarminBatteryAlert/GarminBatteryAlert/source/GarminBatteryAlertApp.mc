import Toybox.Application;
import Toybox.Background;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

(:background)
class GarminBatteryAlertApp extends Application.AppBase {

    private const BACKGROUND_INTERVAL_SECONDS = 5 * 60;

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
    }

    private function ensureBackgroundSchedule() as Void {
        // Schedule-status persistence is diagnostic only. It must never gate scheduling.
        saveScheduleStatusBestEffort("Not verified");

        try {
            var registeredTime = Background.getTemporalEventRegisteredTime();
            var scheduleIsCurrent = false;

            if (registeredTime instanceof Time.Duration) {
                scheduleIsCurrent = (registeredTime as Time.Duration).value() == BACKGROUND_INTERVAL_SECONDS;
            }

            if (!scheduleIsCurrent) {
                Background.registerForTemporalEvent(new Time.Duration(BACKGROUND_INTERVAL_SECONDS));
            }

            saveScheduleStatusBestEffort("Every 5 min");
        } catch (e) {
            // Prepare the scheduling failure diagnostic before any best-effort write.
            var errorStatus = "Error: " + e.getErrorMessage();
            saveScheduleStatusBestEffort(errorStatus);
        }
    }

    private function saveScheduleStatusBestEffort(status as String) as Void {
        try {
            new BatteryAlertStore().saveScheduleStatus(status);
        } catch (ignored) {
            // Diagnostic persistence must not block scheduling or foreground startup.
        }
    }

    function onStop(state as Dictionary?) as Void {
    }

    (:typecheck(disableBackgroundCheck))
    function getInitialView() as [Views] or [Views, InputDelegates] {
        try {
            ensureBackgroundSchedule();
        } catch (ignored) {
            // Foreground startup must remain usable after any scheduling failure.
        }

        var view = new GarminBatteryAlertView();
        return [view, new GarminBatteryAlertInputDelegate(view)];
    }

    function getServiceDelegate() as [System.ServiceDelegate] {
        return [new GarminBatteryAlertBackground()];
    }
}

function getApp() as GarminBatteryAlertApp {
    return Application.getApp() as GarminBatteryAlertApp;
}
