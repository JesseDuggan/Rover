# ROVER Wireless LAN Development

This workflow keeps the ROVER API on a private local network. It does not configure router port forwarding or expose port 5080 publicly.

## 1. Find the laptop address

Open PowerShell on the Windows laptop:

```powershell
ipconfig
```

Find the IPv4 address for the Wi-Fi adapter used by the phone. It will normally resemble `192.168.x.x`, `10.x.x.x`, or `172.16.x.x` through `172.31.x.x`.

For Windows Mobile Hotspot, use the IPv4 address of the hotspot adapter. It is commonly `192.168.137.1`, but verify it with `ipconfig` rather than assuming it.

## 2. Allow port 5080 on Private networks once

First confirm Windows classifies the connection as Private:

```powershell
Get-NetConnectionProfile
```

In an Administrator PowerShell window, create a Private-profile-only rule:

```powershell
New-NetFirewallRule -DisplayName "ROVER API Development (Private TCP 5080)" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 5080 -Profile Private
```

This rule does not apply to Public network profiles. Remove it when no longer needed:

```powershell
Remove-NetFirewallRule -DisplayName "ROVER API Development (Private TCP 5080)"
```

## 3. Start the API in LAN mode

```powershell
cd C:\Users\jesse\Documents\Codex\2026-08-27\create-a-new-production-quality-asp\SRC\rover_middleware
.\run-rover-api-lan.ps1
```

The script detects an active private IPv4 address, binds Development to `http://0.0.0.0:5080`, and prints both the local URL and phone health-check URL. If Windows Mobile Hotspot has multiple possible adapters, specify the address shown by `ipconfig`:

```powershell
.\run-rover-api-lan.ps1 -LanIp <LAPTOP_PRIVATE_IPV4>
```

The local endpoint remains available at `http://127.0.0.1:5080/health`.

## 4. Test from the Samsung device

Connect the phone or watch to the same private Wi-Fi network, then open this in its browser:

```text
http://<LAPTOP_PRIVATE_IPV4>:5080/health
```

Do not continue until the browser displays the ROVER health response.

## 5. Run Flutter without USB reverse

Enable **Developer options > Wireless debugging** on the Samsung device. Use the pairing address, pairing port, and code shown by Android:

```powershell
adb pair <PHONE_IP>:<PAIRING_PORT>
adb connect <PHONE_IP>:<WIRELESS_DEBUG_PORT>
```

The pairing port and wireless-debug port may be different. Then confirm the device appears:

```powershell
flutter devices
```

Use the wireless launcher:

```powershell
cd C:\Users\jesse\Documents\Codex\2026-08-27\create-a-new-production-quality-asp\SRC\rover_flutter
.\run_rover_android_lan.ps1 -LaptopIp <LAPTOP_PRIVATE_IPV4> -DeviceId <WIRELESS_DEVICE_ID>
```

The equivalent direct Flutter command is:

```powershell
flutter run -d <WIRELESS_DEVICE_ID> --debug --dart-define-from-file=.env.local --dart-define=ROVER_API_BASE_URL=http://<LAPTOP_PRIVATE_IPV4>:5080
```

For an installed debug APK, build it with the same address:

```powershell
flutter build apk --debug --dart-define-from-file=.env.local --dart-define=ROVER_API_BASE_URL=http://<LAPTOP_PRIVATE_IPV4>:5080
```

Android emulator development can omit the override and defaults to `http://10.0.2.2:5080`. Windows and local web development default to `http://127.0.0.1:5080`. Physical Android devices must receive `ROVER_API_BASE_URL` at run or build time.


## Change the API address without rebuilding

Debug builds provide a local endpoint override under **Profile > On-device AI**:

1. Enter `http://<LAPTOP_PRIVATE_IPV4>:5080` in **Development API URL**.
2. Select **Test connection** and confirm the result is `Healthy`.
3. Select **Save API URL**.
4. Return to ROVER and create the walk normally.

The saved address applies immediately to all centralized API clients and survives app restarts. Use this after changing Wi-Fi networks or connecting the laptop to the phone's hotspot. Release builds ignore this saved override and do not display the development controls; release cleartext HTTP also remains disabled.

## Windows Mobile Hotspot

1. Enable Mobile Hotspot in Windows Settings.
2. Connect the Samsung phone or watch to that hotspot.
3. Run `ipconfig` and find the hotspot adapter IPv4 address.
4. Start the API with `-LanIp` using that address.
5. Test `/health` in the device browser before starting Flutter.

After the debug app has been installed once, update **Profile > On-device AI > Development API URL** with the hotspot-assigned laptop address. A rebuild or USB cable is no longer required for subsequent address changes.

## Troubleshooting

- **Timeout:** confirm the API console says it is listening on `0.0.0.0:5080`, test `/health`, and verify both devices are on the same network.
- **Connection refused:** confirm the API is running and `ROVER_API_BASE_URL` contains the laptop address, not the phone address.
- **Public network profile:** the Private-only firewall rule will not apply. Change trusted home/hotspot networks to Private in Windows Settings; do not broaden the firewall rule to Public.
- **Client isolation:** some guest Wi-Fi networks prevent devices from reaching each other. Use a trusted private Wi-Fi network or Windows Mobile Hotspot.
- **Changing address:** DHCP can assign the laptop a new address. Re-run `ipconfig`, restart both launch commands with the new value, or reserve an address in the private router.
- **Android cleartext blocked:** only debug builds permit local HTTP. Rebuild the debug APK with the LAN URL; release builds intentionally require HTTPS.
- **Watch cannot connect:** verify the watch itself is connected to Wi-Fi and can reach the health URL. There is currently no separate Wear OS module in this repository; a future module must include the same debug-only cleartext policy and `INTERNET` permission.
