import Toybox.Background;
import Toybox.Lang;
import Toybox.PersistedContent;
import Toybox.System;
import Toybox.Time;

(:background)
class GarminBatteryAlertBackground extends System.ServiceDelegate {

    private var _store as BatteryAlertStore?;

    function initialize() {
        ServiceDelegate.initialize();
    }

    function onTemporalEvent() as Void {
        var timestamp = 0;
        var errorRawBattery = -1.0;
        var errorDisplayBattery = -1;
        var errorCharging = false;

        try {
            var store = new BatteryAlertStore();
            timestamp = Time.now().value();
            var reading = new BatteryAlertDevice().read();
            errorRawBattery = reading.rawBattery;
            errorDisplayBattery = reading.displayBattery;
            errorCharging = reading.charging;

            var state = store.loadState();
            var decision = state.evaluate(reading.rawBattery, reading.charging);
            store.saveBackgroundResult(state, timestamp, reading, decision);

            var pending = store.loadPendingEvent();
            if (pending == null && state.triggeredEventType != null) {
                pending = new BatteryAlertRelay().createEvent(
                    state.triggeredEventType as String,
                    reading.rawBattery,
                    reading.charging,
                    timestamp
                );
                store.savePendingEvent(pending as BatteryAlertPendingEvent);
            }

            if (pending != null) {
                var relay = new BatteryAlertRelay();
                if (!relay.isConfigured()) {
                    store.saveDeliveryDiagnostic("Pending", "Missing config");
                    Background.exit(null);
                    return;
                }

                _store = store;
                store.saveDeliveryDiagnostic("Pending", "In progress");
                relay.send(pending as BatteryAlertPendingEvent, method(:onRelayResponse));
                return;
            }
        } catch (e) {
            try {
                if (timestamp == 0) {
                    timestamp = Time.now().value();
                }

                var errorStore = new BatteryAlertStore();
                if (errorDisplayBattery < 0) {
                    errorRawBattery = errorStore.loadLastRawBattery();
                    errorDisplayBattery = errorStore.loadLastBattery();
                    errorCharging = errorStore.loadLastCharging();
                }

                errorStore.saveBackgroundError(
                    timestamp,
                    errorRawBattery,
                    errorDisplayBattery,
                    errorCharging,
                    "Background error: " + e.getErrorMessage()
                );
            } catch (ignored) {
                // Background.exit() below remains reachable even if error logging fails.
            }
        }

        Background.exit(null);
    }

    function onRelayResponse(
        responseCode as Number,
        data as Dictionary or String or PersistedContent.Iterator or Null
    ) as Void {
        try {
            var store = _store;
            if (store != null) {
                if (BatteryAlertRelay.responseDelivered(responseCode, data)) {
                    (store as BatteryAlertStore).clearPendingEvent();
                    (store as BatteryAlertStore).saveDeliveryDiagnostic(
                        "Delivered",
                        responseCode.format("%d")
                    );
                } else {
                    (store as BatteryAlertStore).saveDeliveryDiagnostic(
                        "Failed",
                        responseCode.format("%d")
                    );
                }
            }
        } catch (ignored) {
            try {
                var fallbackStore = _store;
                if (fallbackStore != null) {
                    (fallbackStore as BatteryAlertStore).saveDeliveryDiagnostic("Failed", "Callback error");
                }
            } catch (ignoredAgain) {
                // The pending event remains stored; exiting is still mandatory.
            }
        }

        Background.exit(null);
    }
}
