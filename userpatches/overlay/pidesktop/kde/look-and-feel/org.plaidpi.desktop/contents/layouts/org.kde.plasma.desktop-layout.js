// Plaid Pi default desktop for new Plasma users: Plasma's default panel, with Plaid Pi's launchers in the task
// manager (the same apps as the GNOME edition's dock) and the Plaid wallpaper.
loadTemplate("org.kde.plasma.desktop.defaultPanel")

var launchers = ["org.kde.dolphin.desktop", "google-chrome.desktop", "chromium.desktop", "firefox.desktop",
                 "mpv.desktop", "org.kde.konsole.desktop", "systemsettings.desktop", "libreoffice-startcenter.desktop",
                 "org.gnome.Rhythmbox3.desktop", "codium.desktop", "thunderbird.desktop", "pro-updates.desktop",
                 "audacity.desktop"].map(function (d) { return "applications:" + d; });
panels().forEach(function (p) {
    p.widgets("org.kde.plasma.icontasks").forEach(function (w) {
        w.currentConfigGroup = ["General"];
        w.writeConfig("launchers", launchers);
    });
});

var desktopsArray = desktopsForActivity(currentActivity());
for (var j = 0; j < desktopsArray.length; j++) {
    desktopsArray[j].wallpaperPlugin = "org.kde.image";
    desktopsArray[j].currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
    desktopsArray[j].writeConfig("Image", "file:///usr/share/wallpapers/PlaidPi/contents/images/3840x2160.png");
}
