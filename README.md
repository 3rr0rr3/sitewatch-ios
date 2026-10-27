# SiteWatch for iPhone

Native iOS 17+ app for network inventories across several locations, recorded switch uplink chains, and TCP management-port checks. The interface is in Spanish.

Download the **SiteWatch-unsigned.ipa** file from [Releases](../../releases). Sign it using Sideloadly or AltStore before installing it on your iPhone. An unsigned IPA cannot be installed directly or uploaded to TestFlight.

## Features

- Add and edit switches and routers, grouped by site.
- Record the upstream device and local/remote port descriptions.
- Select the first switch to view its recorded uplink chain.
- Check a configured TCP management port (443 by default) while the app is open.
- Flag repeated failed checks while preserving uncertainty about the cause.
- Import and export the common fields of the Windows version's devices.json.
- Keep inventories and the latest 500 events locally on the iPhone.

## Limits

Connections are recorded manually, not automatically discovered. SNMP/LLDP discovery, FortiGate integration, separate gateway/internet/DNS diagnostics, and continuous background monitoring are not implemented. An unmanaged switch cannot be individually checked without a management address. A closed or filtered TCP port does not prove that a switch is powered off. The iPhone must have network routes to the configured addresses.

The app requests Local Network permission. No management credentials, real network inventories, or Windows executables are included in this repository.

## Build

On a Mac with Xcode and XcodeGen installed, run `bash ios/build-ipa.sh`. It executes the topology/compatibility tests, builds an arm64 device app, and packages `ios/build/SiteWatch-unsigned.ipa` without signing. The GitHub workflow also verifies a simulator launch and publishes a separate release containing the IPA. It uses no Apple signing secrets.

The Windows application remains a separate artifact and is not changed by this repository.
