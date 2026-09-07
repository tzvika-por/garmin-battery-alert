import Toybox.Application;
import Toybox.Communications;
import Toybox.Cryptography;
import Toybox.Lang;
import Toybox.PersistedContent;
import Toybox.StringUtil;

(:background)
class BatteryAlertRelay {

    const PROPERTY_API_KEY = "RelayApiKey";
    const PROPERTY_BASE_URL = "RelayBaseUrl";

    function createEvent(
        eventType as String,
        battery as Float,
        charging as Boolean,
        timestamp as Number
    ) as BatteryAlertPendingEvent {
        var randomBytes = Cryptography.randomBytes(8);
        var randomHex = StringUtil.convertEncodedString(randomBytes, {
            :fromRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY,
            :toRepresentation => StringUtil.REPRESENTATION_STRING_HEX
        }) as String;
        var eventId = "gba-" + timestamp.format("%d") + "-" + randomHex;
        var message = messageForEventType(eventType);

        return new BatteryAlertPendingEvent(
            eventId,
            eventType,
            battery,
            charging,
            message,
            timestamp
        );
    }

    static function messageForEventType(eventType as String) as String {
        if (eventType.equals("low_battery")) {
            return "Garmin battery is critically low";
        }

        if (eventType.equals("full_charge")) {
            return "Garmin battery is fully charged";
        }

        return "Garmin Battery Alert watch background test";
    }

    function getApiKey() as String {
        var value = Application.Properties.getValue(PROPERTY_API_KEY);
        return value instanceof String ? value as String : "";
    }

    function getBaseUrl() as String {
        var value = Application.Properties.getValue(PROPERTY_BASE_URL);
        return value instanceof String ? value as String : "";
    }

    function isConfigured() as Boolean {
        return getApiKey().length() > 0 && getBaseUrl().length() > 0;
    }

    function send(
        event as BatteryAlertPendingEvent,
        callback as Method(responseCode as Number, data as Dictionary or String or PersistedContent.Iterator or Null) as Void
    ) as Void {
        var headers = {
            "Authorization" => "Bearer " + getApiKey(),
            "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON
        };
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_POST,
            :headers => headers,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };

        Communications.makeWebRequest(
            getBaseUrl() + "/alert",
            event.toPayload(),
            options,
            callback
        );
    }

    static function responseDelivered(responseCode as Number, data as Object?) as Boolean {
        if (responseCode != 200 || !(data instanceof Dictionary)) {
            return false;
        }

        var delivered = (data as Dictionary)["delivered"];
        if (!(delivered instanceof Boolean)) {
            return false;
        }

        return delivered as Boolean;
    }
}
