import Toybox.Application.Storage;
import Toybox.Lang;

(:background)
class BatteryAlertStore {

    const KEY_LOW_ARMED = "gba.lowArmed";
    const KEY_FULL_ARMED = "gba.fullArmed";
    const KEY_LAST_CHECK = "gba.lastCheck";
    const KEY_LAST_BATTERY = "gba.lastBattery";
    const KEY_LAST_RAW_BATTERY = "gba.lastRawBattery";
    const KEY_LAST_CHARGING = "gba.lastCharging";
    const KEY_LAST_DECISION = "gba.lastDecision";
    const KEY_SCHEDULE_STATUS = "gba.scheduleStatus";
    const KEY_PENDING_EVENT = "gba.pendingEvent";
    const KEY_DELIVERY_STATUS = "gba.deliveryStatus";
    const KEY_LAST_HTTP = "gba.lastHttp";
    const KEY_TEST_ACTION = "gba.testAction";

    function loadState() as BatteryAlertState {
        return new BatteryAlertState(
            loadBoolean(KEY_LOW_ARMED, true),
            loadBoolean(KEY_FULL_ARMED, true)
        );
    }

    function saveBackgroundResult(
        state as BatteryAlertState,
        timestamp as Number,
        reading as BatteryAlertReading,
        decision as String
    ) as Void {
        Storage.setValue(KEY_LOW_ARMED, state.lowArmed);
        Storage.setValue(KEY_FULL_ARMED, state.fullArmed);
        Storage.setValue(KEY_LAST_CHECK, timestamp);
        Storage.setValue(KEY_LAST_BATTERY, reading.displayBattery);
        Storage.setValue(KEY_LAST_RAW_BATTERY, reading.rawBattery);
        Storage.setValue(KEY_LAST_CHARGING, reading.charging);
        Storage.setValue(KEY_LAST_DECISION, formatDecision(reading.rawBattery, decision));
    }

    function saveBackgroundError(
        timestamp as Number,
        rawBattery as Float,
        displayBattery as Number,
        charging as Boolean,
        decision as String
    ) as Void {
        Storage.setValue(KEY_LAST_CHECK, timestamp);
        Storage.setValue(KEY_LAST_BATTERY, displayBattery);
        Storage.setValue(KEY_LAST_RAW_BATTERY, rawBattery);
        Storage.setValue(KEY_LAST_CHARGING, charging);
        Storage.setValue(KEY_LAST_DECISION, formatDecision(rawBattery, decision));
    }

    function saveScheduleStatus(status as String) as Void {
        Storage.setValue(KEY_SCHEDULE_STATUS, status);
    }

    function loadScheduleStatus() as String {
        var value = Storage.getValue(KEY_SCHEDULE_STATUS);
        return value == null ? "Not verified" : value as String;
    }

    function loadLastCheck() as Number? {
        var value = Storage.getValue(KEY_LAST_CHECK);
        return value == null ? null : value as Number;
    }

    function loadLastBattery() as Number {
        var value = Storage.getValue(KEY_LAST_BATTERY);
        return value == null ? -1 : value as Number;
    }

    function loadLastRawBattery() as Float {
        var value = Storage.getValue(KEY_LAST_RAW_BATTERY);
        return value == null ? -1.0 : value as Float;
    }

    function loadLastCharging() as Boolean {
        return loadBoolean(KEY_LAST_CHARGING, false);
    }

    function loadLastDecision() as String {
        var value = Storage.getValue(KEY_LAST_DECISION);
        return value == null ? "Not yet" : value as String;
    }

    function savePendingEvent(event as BatteryAlertPendingEvent) as Void {
        Storage.setValue(KEY_PENDING_EVENT, event.toDictionary());
        Storage.setValue(KEY_DELIVERY_STATUS, "Pending");
        Storage.setValue(KEY_LAST_HTTP, "Not attempted");
    }

    function loadPendingEvent() as BatteryAlertPendingEvent? {
        var value = Storage.getValue(KEY_PENDING_EVENT);
        if (!(value instanceof Dictionary)) {
            return null;
        }

        return BatteryAlertPendingEvent.fromDictionary(value as Dictionary);
    }

    function clearPendingEvent() as Void {
        Storage.deleteValue(KEY_PENDING_EVENT);
    }

    function saveDeliveryDiagnostic(status as String, httpStatus as String) as Void {
        Storage.setValue(KEY_DELIVERY_STATUS, status);
        Storage.setValue(KEY_LAST_HTTP, httpStatus);
    }

    function loadDeliveryStatus() as String {
        var value = Storage.getValue(KEY_DELIVERY_STATUS);
        return value == null ? "Not attempted" : value as String;
    }

    function loadLastHttp() as String {
        var value = Storage.getValue(KEY_LAST_HTTP);
        return value == null ? "Not attempted" : value as String;
    }

    function saveTestAction(status as String) as Void {
        Storage.setValue(KEY_TEST_ACTION, status);
    }

    function loadTestAction() as String {
        var value = Storage.getValue(KEY_TEST_ACTION);
        return value == null ? "Tap: Queue relay test" : value as String;
    }

    private function loadBoolean(key as String, defaultValue as Boolean) as Boolean {
        var value = Storage.getValue(key);
        return value == null ? defaultValue : value as Boolean;
    }

    private function formatDecision(rawBattery as Float, decision as String) as String {
        if (rawBattery < 0.0) {
            return decision;
        }

        return rawBattery.format("%.1f") + "% " + decision;
    }
}
