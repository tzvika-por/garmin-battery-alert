import Toybox.Lang;

(:background)
class BatteryAlertState {

    var lowArmed as Boolean;
    var fullArmed as Boolean;
    var triggeredEventType as String?;

    function initialize(initialLowArmed as Boolean, initialFullArmed as Boolean) {
        lowArmed = initialLowArmed;
        fullArmed = initialFullArmed;
        triggeredEventType = null;
    }

    function evaluate(rawBattery as Float, charging as Boolean) as String {
        var decision = "";
        triggeredEventType = null;

        if (!lowArmed && rawBattery >= 10.0) {
            lowArmed = true;
            decision = appendDecision(decision, "Low alert rearmed");
        }

        if (!fullArmed && !charging && rawBattery <= 95.0) {
            fullArmed = true;
            decision = appendDecision(decision, "Full alert rearmed");
        }

        if (lowArmed && rawBattery <= 5.0 && !charging) {
            lowArmed = false;
            triggeredEventType = "low_battery";
            decision = appendDecision(decision, "Low alert triggered; queued");
        }

        if (fullArmed && rawBattery >= 99.0 && charging) {
            fullArmed = false;
            triggeredEventType = "full_charge";
            decision = appendDecision(decision, "Full alert triggered; queued");
        }

        return decision.length() == 0 ? "No state change" : decision;
    }

    private function appendDecision(current as String, next as String) as String {
        return current.length() == 0 ? next : current + "; " + next;
    }
}
