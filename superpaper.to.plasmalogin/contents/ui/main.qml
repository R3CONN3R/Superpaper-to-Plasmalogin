import QtQuick
import QtQuick.Window
import QtCore
import Qt.labs.folderlistmodel
import org.kde.plasma.plasmoid

WallpaperItem {
    id: root
    property bool debugEnabled: false

    property string wallpaperDirectoryLock: StandardPaths.writableLocation(StandardPaths.GenericCacheLocation) + "/superpaper/temp"
    property string wallpaperDirectoryLogin: "file://" + "/var/lib/plasmalogin/wallpapers"

    property string cropZero: ""
    property string cropOne: ""

    /*
     * The screen at virtual X <= 0 receives crop-0.
     * The other screen receives crop-1.
     */
    property int screenNumber: Screen.virtualX <= 0 ? 0 : 1
    property int screenWidth: Screen.height
    property int screenHeight: Screen.width

    function logger(level, message) {
        if (level == "info") {
            console.log("[Superpaper to Plasmalogin]  INFO " + message);
        }
        if (level == "warn") {
            console.warn("[Superpaper to Plasmalogin]  WARN " + message);
        }
        if (level == "debug" && root.debugEnabled) {
            console.log("[Superpaper to Plasmalogin] DEBUG " + message);
        }
    }

    FolderListModel {
        id: filesLogin

        folder: root.wallpaperDirectoryLogin
        nameFilters: ["*.png"]
        showDirs: false
        showFiles: true
        showOnlyReadable: true
        showHidden: true
        sortField: FolderListModel.Name

        onStatusChanged: {
            if (status === FolderListModel.Ready && count > 0) {
                root.logger("debug", "FolderListModel filesLogin ready");
                root.findWallpaperPair(filesLogin);
            }
        }
    }

    FolderListModel {
        id: filesLock

        folder: root.wallpaperDirectoryLock
        nameFilters: ["*.png"]
        showDirs: false
        showFiles: true
        showOnlyReadable: true
        showHidden: true
        sortField: FolderListModel.Name

        onStatusChanged: {
            if (status === FolderListModel.Ready && count > 0) {
                root.logger("debug", "FolderListModel filesLock ready");
                root.findWallpaperPair(filesLock);
            }
        }
    }

    /*
     * The image shown by this particular wallpaper instance.
     */
    Image {
        id: wallpaperImage

        anchors.fill: parent

        asynchronous: true
        cache: false
        smooth: true
        fillMode: Image.PreserveAspectCrop

        source: root.screenNumber === 0 ? root.cropZero : root.cropOne

        onStatusChanged: {
            root.logger("info", "Applied " + source + " to screenNumber: " + root.screenNumber);
            if (status === Image.Error) {
                root.logger("warn", "Failed to load displayed image: " + source);
            }
        }
    }

    function findWallpaperPair(flmodel) {
        root.logger("debug", "executing findWallpaperPair");

        /*
         * Matches:
         *
         * profile-a-crop-0.png
         * profile-a-crop-1.png
         * profile-b-crop-0.png
         * profile-b-crop-1.png
         *
         */
        var pattern = /^(.*)-(a|b)-crop-(0|1)\.png$/;

        root.logger("debug", "Found " + flmodel.count + " image file(s)");

        for (var i = 0; i < flmodel.count; ++i) {
            var fileName = flmodel.get(i, "fileName");
            var fileUrl = flmodel.get(i, "fileUrl");

            root.logger("debug", "Examining file: " + fileName);

            var match = pattern.exec(fileName);

            if (!match) {
                root.logger("debug", "Filename did not match expected pattern");
                continue;
            }

            var profile = match[1];
            var variant = match[2];
            var crop = match[3];

            root.logger("debug", "Matched profile='" + profile + "', variant='" + variant + "', crop='" + crop + "'");

            if (crop === "0") {
                root.cropZero = fileUrl;
            } else {
                root.cropOne = fileUrl;
            }
        }
    }

    Component.onCompleted: {
        root.logger("info", "Wallpaper plugin started for screen " + root.screenNumber);
    }
}
