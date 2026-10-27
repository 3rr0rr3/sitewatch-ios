SiteWatch for iPhone — native SwiftUI version (iOS 17+)

Build status: source prepared. A macOS/Xcode build is required to produce the IPA.
This folder and its ZIP are source code, not an installable IPA.

On a Mac with Xcode and XcodeGen installed:
  bash build-ipa.sh
Output: build/SiteWatch-unsigned.ipa

The unsigned IPA MUST be signed before installation. It is not a TestFlight upload.
For Apple distribution, configure the signing team, identifier and provisioning in
the generated Xcode project and archive/export using the appropriate profile.
Never put certificates, passwords or Apple account details in source files.

Features:
- Native Spanish interface: inventory by site, editable recorded uplinks, route view.
- Configurable TCP check per managed device, default 443 (HTTPS).
- Three consecutive failed TCP checks produce an uncertain reachability alert.
- Checks only while active; paused/background results are discarded.
- Local inventory and 500 recent events stored in the app Documents directory.
- Import/export devices.json compatible with common Windows inventory fields.

Differences from Windows:
- No Windows ping subprocess; native Network.framework TCP checks instead.
- A closed or filtered port does not prove the device is offline.
- A successful connection does not verify every link or internet connectivity.
- The iPhone's path begins at its Wi-Fi access point or Ethernet adapter.
- No automatic local switch detection, LLDP/SNMP discovery, FortiGate API,
  separate gateway/internet/DNS diagnostics, or continuous background monitoring yet.
- Management IPs must be reachable from this iPhone via Wi-Fi/Ethernet/VPN.
- Local Network permission is required.

Unlike the Windows portable folder, an IPA must be signed and installed on iOS.
No special background, VPN, multicast, or packet-capture entitlements are requested.
