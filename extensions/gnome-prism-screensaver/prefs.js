import { ExtensionPreferences } from "resource:///org/gnome/Shell/Extensions/js/extensions/prefs.js";

import { GeneralPage } from "./ui/general_page.js";
import { ScreensaverPage } from "./ui/screensaver_page.js";
import { AppearancePage } from "./ui/appearance_page.js";
import { PromptPage } from "./ui/prompt_page.js";
import { AboutPage } from "./ui/about_page.js";

export default class GnomePrismScreensaverPrefs extends ExtensionPreferences {
    fillPreferencesWindow(window) {
        const settings = this.getSettings();

        window.set_default_size(500, 600);
        window.set_search_enabled(true);

        window.add(new GeneralPage(settings));
        window.add(new ScreensaverPage(settings));
        window.add(new AppearancePage(settings));
        window.add(new PromptPage(settings));
        window.add(new AboutPage(this.metadata, this.path));
    }
}
