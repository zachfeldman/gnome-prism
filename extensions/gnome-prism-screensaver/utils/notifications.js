import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as MessageTray from 'resource:///org/gnome/shell/ui/messageTray.js';

export function sendErrorNotification(message) {
    const source = new MessageTray.Source({
        title: 'GNOME Prism Screensaver',
        iconName: 'dialog-error-symbolic',
    });

    Main.messageTray.add(source);

    const notification = new MessageTray.Notification({
        source,
        title: 'GNOME Prism Screensaver',
        body: message,
        urgency: MessageTray.Urgency.HIGH,
    });

    source.addNotification(notification);
}