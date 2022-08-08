# PWRMON

PWRMON v0.1b3 - Asus-Merlin Tesla Powerwall Monitor by Viktor Jaep, 2022

PWRMON is a shell script that provides near-realtime stats about your Tesla Powerwall/Solar environment. This utility will show all the current electrical loads being generated or consumed by your solar system, the grid, your home and your Powerwall(s). Electrical transmission flows are accurately being depicted using >> and << types of arrows, as electricity moves between your solar, to/from your batteries, to/from the grid and to your home. In the event of a electrical grid outage, PWRMON will calculate your estimated remaining runtime left on your batteries based on the amount of kW being consumed by your home.

Instead of having to find this information on various different web pages or apps, this tool was built to bring all this info together in one stat dashboard.  Having a 'system' dashboard showing current solar, grid, home and powerwall stats would compliment other dashboard-like scripts greatly (like RTRMON or VPNMON-R2), sitting side-by-side in their own SSH windows to give you everything you need to know with a glance at your screen.

Requirements:
-------------

1.) You must be running Asus-Merlin firmware, entware and jffs scripts enabled and installed.

2.) You must have a locally accessible Tesla Gateway device, reachable through your LAN (A Tesla Gateway is a device that monitors and distributes power between your solar, grid, home and batteries. It's very possible to run this setup if you only have batteries, or only have solar, but a Gateway device is still necessary)

3.) You will need to make absolutely sure your email address and password are correct in order to be able to log into your Tesla Gateway. A good way to initially test it is to browse to your Tesla Gateway (ex: https://192.168.45.22), and making some attempts to log in there there first. Your default password to log into your Tesla Gateway is typically a 5-letter alpha upper-case combination that's found on a sticker inside your Tesla Gateway enclosure. It's also the same password you would use to authenticate to the Tesla Gateway TEG-### Wi-Fi network.
