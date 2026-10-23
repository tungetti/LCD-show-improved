# LCD-show-improved

A security-hardened, modernized fork of [`goodtft/LCD-show`](https://github.com/goodtft/LCD-show) for Raspberry Pi GPIO/SPI and HDMI displays, featuring **Dynamic Multi-Screen HDMI Priority** (`LCD35-multiscreen-show`).

---

## What Was Improved Compared to `goodtft/LCD-show`

1. **Dynamic Multi-Screen HDMI Priority (`LCD35-multiscreen-show`)**:
   - Uses KMS/DRM (`vc4-kms-v3d` + `piscreen,drm`) and a lightweight desktop daemon (`lcd35-multiscreen-daemon.sh`) instead of locking Xorg to a single legacy framebuffer (`fbturbo`).
   - **0 HDMI cables connected**: The 3.5" SPI LCD acts as the **1st (primary) screen**.
   - **1 HDMI cable connected**: `HDMI-1` becomes the **1st (primary) screen**, and the 3.5" SPI LCD automatically shifts to the **2nd screen** (extended to the right).
   - **2 HDMI cables connected**: `HDMI-1` is the **1st screen**, `HDMI-2` is the **2nd screen**, and the 3.5" SPI LCD automatically shifts to the **3rd screen**.
   - **Automatic Touchscreen Mapping**: Automatically binds the `ADS7846 Touchscreen` input coordinates to the 3.5" LCD rectangle via `xinput map-to-output`, so touching the 3.5" screen only clicks inside the 3.5" screen even when 1 or 2 HDMI monitors are attached.
2. **SSH-Safe `.bash_profile`**:
   - Guards `startx` so it only launches on local physical console `/dev/tty1` when `SSH_CONNECTION` and `DISPLAY` are unset. Logging in via SSH will no longer accidentally hijack or crash the X11 session, and `~/.profile` is preserved.
3. **Password-Protected Login by Default**:
   - Unlike upstream `LCD-show` which silently forced passwordless console/desktop autologin (`B2`/`B4`), this repository defaults to password-protected login (`B1`/`B3`). Passwordless autologin for headless/keyboardless setups remains available via `LCD_AUTOLOGIN=1`.
4. **Immutable, Non-Destructive System Backups (`.system_backup`)**:
   - The initial backup of `/boot/config.txt`, `/boot/cmdline.txt`, `/etc/X11/xorg.conf.d/`, and `~/.bash_profile` is taken once and locked with `.system_backup/.backup_complete`. Re-running driver scripts or switching modes never overwrites your original system backup.
5. **Removed Third-Party Plain-HTTP Probes**:
   - Removed hardcoded plain-HTTP connectivity checks to `http://mirrors.zju.edu.cn`.
6. **Proper Debian Version Comparisons & Safe Boot Config**:
   - Replaced broken bash string comparisons (`"$deb_version" < "12.1"`) with `dpkg --compare-versions`.
   - Disabled hardcoded `PARTUUID` `cmdline.txt` overwrites that could render SD/NVMe installations unbootable.

---

## Step-by-Step Installation on Raspberry Pi

### Step 1: Clone the Repository

Connect to your Raspberry Pi via SSH or terminal (ensure an active internet connection for `apt` packages) and run:

```bash
git clone https://github.com/tungetti/LCD-show-improved.git
chmod -R 755 LCD-show-improved
cd LCD-show-improved
```

---

### Step 2: Choose Your Display Mode

#### Option A (Recommended for 3.5" MPI3501): Dynamic Multi-Screen Mode

```bash
sudo ./LCD35-multiscreen-show
```

*(Optional: pass a rotation angle `0`, `90`, `180`, or `270`, e.g. `sudo ./LCD35-multiscreen-show 90`. By default, no argument or `0` sets the standard `0°` landscape orientation (`rotate=90` in the hardware overlay), and passing `90`, `180`, or `270` rotates relative to that default orientation just like `LCD35-show` and `rotate.sh`.)*

**How Dynamic Multi-Screen Priority works:**
- **Standalone (0 HDMI cables plugged in)**: The 3.5" LCD is your primary desktop (`0x0`).
- **1 HDMI monitor plugged in (at boot or hotplugged)**: The HDMI monitor automatically becomes the **1st (primary) screen**, and the 3.5" LCD becomes the **2nd screen** to its right.
- **2 HDMI monitors plugged in (at boot or hotplugged)**: `HDMI-1` is the **1st screen**, `HDMI-2` is the **2nd screen**, and the 3.5" LCD becomes the **3rd screen** to the right of `HDMI-2`.
- **Unplugging HDMI cables**: Automatically promotes the 3.5" LCD back up to 2nd or 1st primary screen and remaps touch input accordingly.

---

#### Option B: Classic Single-Screen Mode (`LCD35-show` & Other Displays)

If you want classic single-screen mode (or are using another supported LCD model), run the corresponding script below:

| Display Model | Size / Interface | Command | Wiki |
|---|---|---|---|
| **MPI3501** (Multi-Screen Mode) | 3.5" GPIO/SPI (Resistive) | `sudo ./LCD35-multiscreen-show` | [Wiki](http://www.lcdwiki.com/3.5inch_RPi_Display) |
| **MPI3501** (Classic Single-Screen) | 3.5" GPIO/SPI (Resistive) | `sudo ./LCD35-show` | [Wiki](http://www.lcdwiki.com/3.5inch_RPi_Display) |
| **MPI2401** | 2.4" GPIO/SPI | `sudo ./LCD24-show` | [Wiki](http://www.lcdwiki.com/2.4inch_RPi_Display) |
| **MPI2411** (For RPi 3A+) | 2.4" GPIO/SPI | `sudo ./LCD24-3A+-show` | [Wiki](http://www.lcdwiki.com/2.4inch_RPi_Display_For_RPi_3A+) |
| **MPI2801** | 2.8" GPIO/SPI | `sudo ./LCD28-show` | [Wiki](http://www.lcdwiki.com/2.8inch_RPi_Display) |
| **MPI3201** | 3.2" GPIO/SPI | `sudo ./LCD32-show` | [Wiki](http://www.lcdwiki.com/3.2inch_RPi_Display) |
| **MHS3232** | 3.2" GPIO/SPI (MHS) | `sudo ./MHS32-show` | [Wiki](http://www.lcdwiki.com/MHS-3.2inch_Display) |
| **MHS3528** | 3.5" GPIO/SPI (MHS) | `sudo ./MHS35-show` | [Wiki](http://www.lcdwiki.com/MHS-3.5inch_RPi_Display) |
| **MHS35XX** | 3.5" GPIO/SPI (MHS-B) | `sudo ./MHS35B-show` | [Wiki](http://www.lcdwiki.com/MHS-3.5inch_RPi_Display-B) |
| **MHS35IPS** | 3.5" GPIO/SPI (IPS) | `sudo ./MHS35IPS-show` | - |
| **MIS35** | 3.5" GPIO/SPI | `sudo ./MIS35-show` | - |
| **MPI3508** | 3.5" HDMI-B | `sudo ./MPI3508-show` | [Wiki](http://www.lcdwiki.com/3.5inch_HDMI_Display-B) |
| **MPI4008** | 4.0" HDMI-C | `sudo ./MPI4008-show` | [Wiki](http://www.lcdwiki.com/4inch_HDMI_Display-C) |
| **MHS4001** | 4.0" GPIO/SPI (MHS) | `sudo ./MHS40-show` | [Wiki](http://www.lcdwiki.com/MHS-4.0inch_Display-B) |
| **MHS40C** | 4.0" GPIO/SPI (Capacitive) | `sudo ./MHS40C-show` | - |
| **MPI5008** | 5.0" HDMI (Resistive) | `sudo ./LCD5-show` | [Wiki](http://www.lcdwiki.com/5inch_HDMI_Display) |
| **MPI5001** | 5.0" HDMI-B (Capacitive) | `sudo ./MPI5001-show` | [Wiki](http://www.lcdwiki.com/5inch_HDMI_Display-B) |
| **MPI7001** | 7.0" HDMI-B (800x480) | `sudo ./LCD7B-show` | [Wiki](http://www.lcdwiki.com/7inch_HDMI_Display-B) |
| **MPI7002** | 7.0" HDMI-C (1024x600) | `sudo ./LCD7C-show` | [Wiki](http://www.lcdwiki.com/7inch_HDMI_Display-C) |

---

### Step 3: Headless / Keyboardless Auto-Login Option

By default, the scripts preserve password authentication at login. If your Raspberry Pi runs without a physical keyboard and needs to boot straight into the desktop on the LCD, pass `LCD_AUTOLOGIN=1`:

```bash
# Dynamic Multi-Screen Mode with Auto-Login:
sudo ./LCD35-multiscreen-show --autologin
# (or: sudo LCD_AUTOLOGIN=1 ./LCD35-multiscreen-show)

# Or Classic Single-Screen Mode with Auto-Login:
sudo LCD_AUTOLOGIN=1 ./LCD35-show
```

---

### Step 4: Screen Rotation

You can rotate the display and touchscreen calibration either during installation or afterwards:

**During driver installation:**
```bash
sudo ./LCD35-multiscreen-show 90
# or
sudo ./LCD35-show 90
```

**After driver installation:**
```bash
cd LCD-show-improved
sudo ./rotate.sh 90
```
*(Supported rotation values: `0`, `90`, `180`, `270`. HDMI screens additionally support `360` for horizontal flip and `450` for vertical flip.)*

---

### Step 5: Switching Back to HDMI Only or Restoring the System

- **Switch to HDMI-only output:**
  ```bash
  cd LCD-show-improved
  sudo ./LCD-hdmi
  ```
- **Full System Restore (reverts all config files to the original pre-install backup in `.system_backup`):**
  ```bash
  cd LCD-show-improved
  sudo ./system_restore.sh
  ```
