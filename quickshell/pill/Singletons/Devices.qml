pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Device-control bridge — owns the external-monitor brightness (ddcutil)
 * integration the mixer drives. DDC-capable monitors are discovered once via
 * `ddcutil detect` (one brightness fader each) rather than hardcoding I2C bus
 * numbers, and the setvcp/getvcp wire format lives here so every caller speaks
 * it identically.
 *
 * Laptop internal panels don't speak DDC/CI at all, so they never show up in
 * `ddcMonitors` — their brightness goes through the kernel backlight class via
 * brightnessctl instead, tracked separately as `hasBacklight`/`backlightPct`.
 */
Singleton {
    id: root

    property bool hasBacklight: false
    property int backlightPct: 0

    /**
     * DDC-capable monitors from `ddcutil detect`: [{ bus, label }] with label
     * taken from the DRM connector, falling back to the I2C bus number.
     */
    property var ddcMonitors: []

    /** Discovers DDC-capable monitors into `ddcMonitors`. */
    function detect() {
        ddcDetect.running = true;
        backlightDetect.running = true;
    }

    /** Writes brightness `pct` to monitor `bus` via ddcutil setvcp. */
    function setBrightness(bus, pct) {
        Quickshell.execDetached(["timeout", "3", "ddcutil", "setvcp", "10",
            String(pct), "--bus", bus, "--noverify"]);
    }

    /** Writes brightness `pct` to the internal panel via brightnessctl. */
    function setBacklight(pct) {
        root.backlightPct = Math.round(pct);
        Quickshell.execDetached(["brightnessctl", "set", Math.round(pct) + "%"]);
    }

    /**
     * Parses a `ddcutil getvcp --brief` line, returning the current brightness
     * percent or -1 when no value is present.
     */
    function parseBrightness(text) {
        var m = text.match(/C\s+(\d+)\s+/);
        return m ? parseInt(m[1], 10) : -1;
    }

    Process {
        id: ddcDetect
        command: ["ddcutil", "detect", "--brief"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var mons = [];
                var blocks = this.text.split(/\bDisplay \d+/);
                for (var i = 0; i < blocks.length; i++) {
                    var bus = /I2C bus:\s+\/dev\/i2c-(\d+)/.exec(blocks[i]);
                    var conn = /DRM connector:\s+card\d+-(\S+)/.exec(blocks[i]);
                    if (bus)
                        mons.push({ bus: bus[1], label: conn ? conn[1] : "BUS " + bus[1] });
                }
                root.ddcMonitors = mons;
            }
        }
    }

    /** `brightnessctl -m` prints `name,class,current,pct%,max`; -1 pct if absent. */
    Process {
        id: backlightDetect
        command: ["brightnessctl", "-m"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var m = /^[^,]*,backlight,\d+,(\d+)%/m.exec(this.text);
                root.hasBacklight = m !== null;
                root.backlightPct = m ? parseInt(m[1], 10) : 0;
            }
        }
    }
}
