import Toybox.Lang;
import Toybox.Test;

(:test)
function testPhaseOneThresholdsAndRearms(logger as Test.Logger) as Boolean {
    var low = new BatteryAlertState(true, true);
    Test.assertEqual("No state change", low.evaluate(5.1, false));
    Test.assert(low.triggeredEventType == null);
    Test.assertEqual("Low alert triggered; queued", low.evaluate(5.0, false));
    Test.assertEqual("low_battery", low.triggeredEventType);
    Test.assertEqual("No state change", low.evaluate(4.0, false));
    Test.assert(low.triggeredEventType == null);
    Test.assertEqual("No state change", low.evaluate(9.9, false));
    Test.assertEqual("Low alert rearmed", low.evaluate(10.0, false));

    var chargingLow = new BatteryAlertState(true, true);
    Test.assertEqual("No state change", chargingLow.evaluate(5.0, true));

    var full = new BatteryAlertState(true, true);
    Test.assertEqual("No state change", full.evaluate(98.9, true));
    Test.assertEqual("Full alert triggered; queued", full.evaluate(99.0, true));
    Test.assertEqual("full_charge", full.triggeredEventType);
    Test.assertEqual("No state change", full.evaluate(100.0, true));
    Test.assert(full.triggeredEventType == null);
    Test.assertEqual("No state change", full.evaluate(95.1, false));
    Test.assertEqual("Full alert rearmed", full.evaluate(95.0, false));
    return true;
}

(:test)
function testPendingEventRoundTripRetainsIdentity(logger as Test.Logger) as Boolean {
    var original = new BatteryAlertPendingEvent(
        "gba-test-stable-id",
        "low_battery",
        5.0,
        false,
        "Garmin battery is critically low",
        12345
    );
    var restored = BatteryAlertPendingEvent.fromDictionary(original.toDictionary());
    Test.assert(restored != null);
    Test.assertEqual(original.eventId, (restored as BatteryAlertPendingEvent).eventId);
    Test.assertEqual(original.eventType, (restored as BatteryAlertPendingEvent).eventType);
    Test.assertEqual(original.battery, (restored as BatteryAlertPendingEvent).battery);
    return true;
}

(:test)
function testRelayResponseClassification(logger as Test.Logger) as Boolean {
    Test.assert(BatteryAlertRelay.responseDelivered(200, {
        "delivered" => true,
        "duplicate" => false
    }));
    Test.assert(BatteryAlertRelay.responseDelivered(200, {
        "delivered" => true,
        "duplicate" => true
    }));
    Test.assert(!BatteryAlertRelay.responseDelivered(500, {"delivered" => true}));
    Test.assert(!BatteryAlertRelay.responseDelivered(401, {"delivered" => false}));
    Test.assert(!BatteryAlertRelay.responseDelivered(200, {"duplicate" => false}));
    Test.assert(!BatteryAlertRelay.responseDelivered(200, "malformed"));
    return true;
}

(:test)
function testForegroundRelayTestEvent(logger as Test.Logger) as Boolean {
    var event = new BatteryAlertRelay().createEvent("test", 80.0, false, 24680);
    Test.assertEqual("test", event.eventType);
    Test.assertEqual("Garmin Battery Alert watch background test", event.message);

    var restored = BatteryAlertPendingEvent.fromDictionary(event.toDictionary());
    Test.assert(restored != null);
    Test.assertEqual(event.eventId, (restored as BatteryAlertPendingEvent).eventId);
    Test.assertEqual("test", (restored as BatteryAlertPendingEvent).eventType);
    return true;
}
