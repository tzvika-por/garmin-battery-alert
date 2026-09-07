import Toybox.Lang;
import Toybox.Math;
import Toybox.System;

(:background)
class BatteryAlertReading {

    var rawBattery as Float;
    var displayBattery as Number;
    var charging as Boolean;

    function initialize(rawValue as Float, normalizedDisplayValue as Number, isCharging as Boolean) {
        rawBattery = rawValue;
        displayBattery = normalizedDisplayValue;
        charging = isCharging;
    }
}

(:background)
class BatteryAlertDevice {

    function read() as BatteryAlertReading {
        // SDK 9.2.0 defines getSystemStats() as System.Stats and battery as Float.
        var stats = System.getSystemStats();
        var rawBattery = stats.battery;
        var normalizedBattery = Math.round(rawBattery) as Number;

        if (normalizedBattery < 0) {
            normalizedBattery = 0;
        } else if (normalizedBattery > 100) {
            normalizedBattery = 100;
        }

        // SDK 9.2.0 defines charging as Boolean (available since API 3.0.0).
        var charging = stats.charging;
        return new BatteryAlertReading(rawBattery, normalizedBattery, charging);
    }
}
