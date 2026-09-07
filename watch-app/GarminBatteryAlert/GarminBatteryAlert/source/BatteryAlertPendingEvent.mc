import Toybox.Application.Storage;
import Toybox.Lang;

(:background)
class BatteryAlertPendingEvent {

    const KEY_EVENT_ID = "event_id";
    const KEY_EVENT_TYPE = "event_type";
    const KEY_BATTERY = "battery";
    const KEY_CHARGING = "charging";
    const KEY_MESSAGE = "message";
    const KEY_CREATED_AT = "created_at";

    var eventId as String;
    var eventType as String;
    var battery as Float;
    var charging as Boolean;
    var message as String;
    var createdAt as Number;

    function initialize(
        newEventId as String,
        newEventType as String,
        newBattery as Float,
        newCharging as Boolean,
        newMessage as String,
        newCreatedAt as Number
    ) {
        eventId = newEventId;
        eventType = newEventType;
        battery = newBattery;
        charging = newCharging;
        message = newMessage;
        createdAt = newCreatedAt;
    }

    function toDictionary() as Dictionary<Storage.KeyType, Storage.ValueType> {
        return {
            KEY_EVENT_ID => eventId,
            KEY_EVENT_TYPE => eventType,
            KEY_BATTERY => battery,
            KEY_CHARGING => charging,
            KEY_MESSAGE => message,
            KEY_CREATED_AT => createdAt
        };
    }

    function toPayload() as Dictionary<Object, Object> {
        return {
            KEY_EVENT_ID => eventId,
            KEY_EVENT_TYPE => eventType,
            KEY_BATTERY => battery,
            KEY_CHARGING => charging,
            KEY_MESSAGE => message
        };
    }

    static function fromDictionary(value as Dictionary) as BatteryAlertPendingEvent? {
        var eventId = value["event_id"];
        var eventType = value["event_type"];
        var battery = value["battery"];
        var charging = value["charging"];
        var message = value["message"];
        var createdAt = value["created_at"];

        if (!(eventId instanceof String) || !(eventType instanceof String) ||
            !(battery instanceof Float) || !(charging instanceof Boolean) ||
            !(message instanceof String) || !(createdAt instanceof Number)) {
            return null;
        }

        return new BatteryAlertPendingEvent(
            eventId as String,
            eventType as String,
            battery as Float,
            charging as Boolean,
            message as String,
            createdAt as Number
        );
    }
}
