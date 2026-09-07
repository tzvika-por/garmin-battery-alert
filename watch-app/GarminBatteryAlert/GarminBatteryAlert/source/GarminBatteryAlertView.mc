import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

class GarminBatteryAlertView extends WatchUi.View {

    private const TITLE_TOP = 14;
    private const TITLE_WIDTH = 190;
    private const BATTERY_COLUMN_WIDTH = 110;
    private const CHARGING_COLUMN_WIDTH = 70;
    private const BODY_WIDTH = 218;
    private const DYNAMIC_WIDTH = 212;
    private const ACTION_WIDTH = 174;

    private var _batteryText as String = "Unavailable";
    private var _chargingText as String = "Unavailable";
    private var _lowStateText as String = "Armed";
    private var _fullStateText as String = "Armed";
    private var _scheduleStatusText as String = "Not verified";
    private var _lastCheckText as String = "Not yet";
    private var _lastDecisionText as String = "Not yet";
    private var _relayText as String = "Missing";
    private var _pendingText as String = "None";
    private var _deliveryText as String = "Not attempted";
    private var _lastHttpText as String = "Not attempted";
    private var _testActionText as String = "Tap: Queue relay test";

    function initialize() {
        View.initialize();
    }

    function onShow() as Void {
        refreshDiagnostics();
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var font = Graphics.FONT_XTINY;
        var fontHeight = dc.getFontHeight(font);
        var center = dc.getWidth() / 2;
        var y = TITLE_TOP;

        drawFittedText(dc, center, y, font, "Garmin Battery Alert", TITLE_WIDTH);

        y += fontHeight + 3;
        drawValueText(dc, center - 52, y, font, "B ", _batteryText, BATTERY_COLUMN_WIDTH);
        drawValueText(dc, center + 60, y, font, "C ", _chargingText, CHARGING_COLUMN_WIDTH);

        y += fontHeight;
        drawFittedText(dc, center, y, font, "Low alert: " + _lowStateText, BODY_WIDTH);
        y += fontHeight;
        drawFittedText(dc, center, y, font, "Full alert: " + _fullStateText, BODY_WIDTH);
        y += fontHeight;
        drawFittedText(dc, center, y, font, "Schedule: " + _scheduleStatusText, DYNAMIC_WIDTH);
        y += fontHeight;
        drawFittedText(dc, center, y, font, "Last check: " + _lastCheckText, BODY_WIDTH);
        y += fontHeight;
        drawFittedText(dc, center, y, font, "Last: " + _lastDecisionText, DYNAMIC_WIDTH);
        y += fontHeight;
        drawFittedText(dc, center, y, font, "Relay: " + _relayText, BODY_WIDTH);
        y += fontHeight;
        drawFittedText(dc, center, y, font, "Pending: " + _pendingText, BODY_WIDTH);
        y += fontHeight;
        drawFittedText(dc, center, y, font, "Delivery: " + _deliveryText, DYNAMIC_WIDTH);
        y += fontHeight;
        drawFittedText(dc, center, y, font, "HTTP: " + _lastHttpText, BODY_WIDTH);
        y += fontHeight;
        drawFittedText(dc, center, y, font, _testActionText, ACTION_WIDTH);
    }

    function queueRelayTest() as Void {
        var store = new BatteryAlertStore();

        try {
            if (store.loadPendingEvent() != null) {
                store.saveTestAction("Refused: Pending exists");
            } else {
                var timestamp = Time.now().value();
                var reading = new BatteryAlertDevice().read();
                var event = new BatteryAlertRelay().createEvent(
                    "test",
                    reading.rawBattery,
                    reading.charging,
                    timestamp
                );
                store.savePendingEvent(event);
                store.saveTestAction("Test queued");
            }
        } catch (e) {
            try {
                store.saveTestAction("Test queue error");
            } catch (ignored) {
                // Foreground interaction remains safe if diagnostic storage fails.
            }
        }

        refreshDiagnostics();
        WatchUi.requestUpdate();
    }

    private function refreshDiagnostics() as Void {
        var store = new BatteryAlertStore();

        try {
            _scheduleStatusText = store.loadScheduleStatus();

            var state = store.loadState();
            _lowStateText = state.lowArmed ? "Armed" : "Disarmed";
            _fullStateText = state.fullArmed ? "Armed" : "Disarmed";

            var reading = new BatteryAlertDevice().read();
            _batteryText = reading.rawBattery.format("%.1f") + "%";
            _chargingText = reading.charging ? "Yes" : "No";

            var lastCheck = store.loadLastCheck();
            _lastCheckText = lastCheck == null ? "Not yet" : formatTimestamp(lastCheck as Number);
            _lastDecisionText = store.loadLastDecision();
            _relayText = new BatteryAlertRelay().isConfigured() ? "Configured" : "Missing";
            var pending = store.loadPendingEvent();
            if (pending == null) {
                _pendingText = "None";
            } else {
                var pendingType = (pending as BatteryAlertPendingEvent).eventType;
                if (pendingType.equals("low_battery")) {
                    _pendingText = "Low";
                } else if (pendingType.equals("full_charge")) {
                    _pendingText = "Full";
                } else {
                    _pendingText = "Test";
                }
            }
            _deliveryText = store.loadDeliveryStatus();
            _lastHttpText = store.loadLastHttp();
            _testActionText = store.loadTestAction();
        } catch (e) {
            _batteryText = "Unavailable";
            _chargingText = "Unavailable";
            _lastDecisionText = "Read error: " + e.getErrorMessage();
        }
    }

    private function formatTimestamp(timestamp as Number) as String {
        var info = Gregorian.info(new Time.Moment(timestamp), Time.FORMAT_SHORT);
        return Lang.format("$1$-$2$-$3$ $4$:$5$", [
            info.year.format("%04d"),
            (info.month as Number).format("%02d"),
            info.day.format("%02d"),
            info.hour.format("%02d"),
            info.min.format("%02d")
        ]);
    }

    private function fitTextToWidth(
        dc as Dc,
        text as String,
        font as Graphics.FontType,
        maximumWidth as Number
    ) as String {
        if (dc.getTextWidthInPixels(text, font) <= maximumWidth) {
            return text;
        }

        var ellipsis = "...";
        var endIndex = text.length();
        while (endIndex > 0) {
            endIndex -= 1;
            var candidate = text.substring(0, endIndex) + ellipsis;
            if (dc.getTextWidthInPixels(candidate, font) <= maximumWidth) {
                return candidate;
            }
        }

        return ellipsis;
    }

    private function drawFittedText(
        dc as Dc,
        x as Number,
        y as Number,
        font as Graphics.FontType,
        text as String,
        maximumWidth as Number
    ) as Void {
        dc.drawText(
            x,
            y,
            font,
            fitTextToWidth(dc, text, font, maximumWidth),
            Graphics.TEXT_JUSTIFY_CENTER
        );
    }

    private function drawValueText(
        dc as Dc,
        x as Number,
        y as Number,
        font as Graphics.FontType,
        label as String,
        value as String,
        maximumWidth as Number
    ) as Void {
        dc.drawText(
            x,
            y,
            font,
            fitLabeledValueToWidth(dc, label, value, font, maximumWidth),
            Graphics.TEXT_JUSTIFY_CENTER
        );
    }

    private function fitLabeledValueToWidth(
        dc as Dc,
        label as String,
        value as String,
        font as Graphics.FontType,
        maximumWidth as Number
    ) as String {
        var labeledValue = label + value;
        if (dc.getTextWidthInPixels(labeledValue, font) <= maximumWidth) {
            return labeledValue;
        }

        if (dc.getTextWidthInPixels(value, font) <= maximumWidth) {
            return value;
        }

        return fitTextToWidth(dc, value, font, maximumWidth);
    }
}
