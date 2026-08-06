pragma Singleton
import QtQuick
import Quickshell

Singleton {
    // Primary accent: Dracula purple (was vermilion)
    readonly property color verm:     "#bd93f9"
    readonly property color vermLit:  "#d6acff"
    readonly property color vermDeep: "#9580ca"
    // Neutral foreground: Dracula foreground tones (was cream/warm)
    readonly property color cream:    "#f8f8f2"
    readonly property color bright:   "#ffffff"
    readonly property color dim:      "#6272a4"
    // Dark surfaces (was warm brown cards)
    readonly property color cardTop:  "#282a36"
    readonly property color cardBot:  "#1e1f29"
    readonly property color border:   "#44475a"
    readonly property color shadow:   Qt.rgba(0, 0, 0, 0.55)
    readonly property color tileBg:   "#191a21"
    readonly property color subtle:   "#a9b1d6"
    readonly property color faint:    "#565f89"
    readonly property color iconDim:  "#cad3f5"
    // Semi-transparent foreground overlays
    readonly property color hair:     Qt.rgba(248/255, 248/255, 242/255, 0.13)
    readonly property color sheen:    Qt.rgba(248/255, 248/255, 242/255, 0.07)
    // Muted accent tones (was muted vermilion)
    readonly property color vermDim:     "#6d5dab"
    readonly property color vermDimDeep: "#4d4190"
    readonly property color vermBurn:    "#7251b5"
    readonly property color tickRest:    "#a9b1d6"
    readonly property color threadBg:    Qt.rgba(0.74, 0.58, 0.976, 0.13)
    // Glow/flame effect in purple tones (was warm orange/amber)
    readonly property color flameCore: "#d6acff"
    readonly property color flameGlow: "#bd93f9"
    /**
     * Canvas gradient hex strings — must not serialize through QML color
     * or the #aarrggbb format corrupts addColorStop.
     */
    readonly property string flameInk:   "#bd93f9"
    readonly property string flameEmber: "#6d4bc2"
    readonly property string flameBurn:  "#7251b5"
    readonly property string flameTip:   "#d6acff"
    readonly property color todayWarm: "#ffb86c"
    readonly property color ghost:     "#44475a"
    readonly property color frameBg:      Qt.rgba(0.53, 0.45, 0.73, 0.055)
    readonly property color frameBorder:  Qt.rgba(0.53, 0.45, 0.73, 0.10)
    readonly property color creamMenu:    Qt.rgba(0.157, 0.165, 0.212, 0.82)
    readonly property real shadowOpacity: 0.5
    readonly property string font: "Inter"
    readonly property string fontJp: "Noto Sans CJK JP"

    /**
     * MPRIS trackArtists arrives as a JS array from some players and as a
     * plain string from others (Spotify); calling join on the string throws
     * and kills the whole binding. Normalizes both, with trackArtist as
     * fallback.
     */
    function joinArtists(artists, single) {
        if (artists && typeof artists.join === "function" && artists.length > 0)
            return artists.join(", ");
        if (artists && String(artists).length > 0)
            return String(artists);
        return single ? String(single) : "";
    }
}
