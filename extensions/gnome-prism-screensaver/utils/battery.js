import Gio from 'gi://Gio';

export function isOnBattery() {
    try {
        const upower = Gio.DBusProxy.new_for_bus_sync(
            Gio.BusType.SYSTEM,
            Gio.DBusProxyFlags.NONE,
            null,
            'org.freedesktop.UPower',
            '/org/freedesktop/UPower',
            'org.freedesktop.UPower',
            null
        );
        return upower.get_cached_property('OnBattery')?.unpack() ?? false;
    } catch (e) {
        return false;
    }
}